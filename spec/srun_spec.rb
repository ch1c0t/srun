require_relative 'helper'

describe 'srun execution modes' do
  before do
    @project = Dir.mktmpdir('srun-project-')
    @fake_crystal_env = install_fake_crystal(@project)
  end

  after do
    FileUtils.remove_entry(@project) if @project && Dir.exist?(@project)
  end

  def invoke_srun(*arguments, extra_env: {})
    run_srun(
      *arguments,
      chdir: @project,
      env: @fake_crystal_env.merge(extra_env)
    )
  end

  def invocation_lines
    path = @fake_crystal_env.fetch('SRUN_FAKE_CRYSTAL_LOG')
    File.file?(path) ? File.readlines(path, chomp: true) : []
  end

  def report_contents
    File.read(File.join(run_directory(@project), 'report.txt'))
  end

  it 'defaults to specs when scen does not exist and keeps one process per spec file' do
    FileUtils.mkdir_p(File.join(@project, 'spec', 'unit'))
    File.write(File.join(@project, 'spec', 'unit', 'a_spec.cr'), "puts :a\n")
    File.write(File.join(@project, 'spec', 'unit', 'b_spec.cr'), "puts :b\n")

    stdout, stderr, status = invoke_srun

    expect(status.exitstatus).to eq(0), stderr
    expect(invocation_lines.map { |line| line.split('|', 2).last }).to eq([
      'spec spec/unit/a_spec.cr',
      'spec spec/unit/b_spec.cr',
    ])
    expect(invocation_lines.map { |line| line.split('|', 2).first }.uniq.size).to eq(2)
    expect(report_contents).to include('PASS: spec/unit/a_spec.cr')
    expect(report_contents).to include('PASS: spec/unit/b_spec.cr')
    expect(stdout).to include('srun specs finished: 2 passed, 0 failed')
  end

  it 'defaults to scenarios when scen exists and lists every recursive match in the report' do
    FileUtils.mkdir_p(File.join(@project, 'scen', 'nested', 'deeper'))
    File.write(File.join(@project, 'scen', 'first.scen.cr'), "puts :first\n")
    File.write(File.join(@project, 'scen', 'nested', 'deeper', 'second.scen.cr'), "puts :second\n")
    FileUtils.mkdir_p(File.join(@project, 'spec'))
    File.write(File.join(@project, 'spec', 'ignored_spec.cr'), "puts :ignored\n")

    stdout, stderr, status = invoke_srun

    expect(status.exitstatus).to eq(0), stderr
    expect(invocation_lines.map { |line| line.split('|', 2).last }).to eq([
      'run scen/first.scen.cr',
      'run scen/nested/deeper/second.scen.cr',
    ])
    expect(invocation_lines.map { |line| line.split('|', 2).first }.uniq.size).to eq(2)
    expect(report_contents).to include('PASS: scen/first.scen.cr')
    expect(report_contents).to include('PASS: scen/nested/deeper/second.scen.cr')
    expect(report_contents).not_to include('ignored_spec.cr')
    expect(stdout).to include('srun scenarios finished: 2 passed, 0 failed')
  end

  it 'runs specs explicitly even when scen exists' do
    FileUtils.mkdir_p(File.join(@project, 'scen'))
    File.write(File.join(@project, 'scen', 'scenario.scen.cr'), "puts :scenario\n")
    FileUtils.mkdir_p(File.join(@project, 'spec'))
    File.write(File.join(@project, 'spec', 'only_spec.cr'), "puts :spec\n")

    stdout, stderr, status = invoke_srun('specs')

    expect(status.exitstatus).to eq(0), stderr
    expect(invocation_lines.map { |line| line.split('|', 2).last }).to eq([
      'spec spec/only_spec.cr',
    ])
    expect(report_contents).to include('PASS: spec/only_spec.cr')
    expect(report_contents).not_to include('scenario.scen.cr')
    expect(stdout).to include('srun specs finished: 1 passed, 0 failed')
  end

  it 'runs scenarios explicitly and records failing scenario names and exit statuses' do
    FileUtils.mkdir_p(File.join(@project, 'scen', 'acceptance'))
    File.write(File.join(@project, 'scen', 'acceptance', 'fails.scen.cr'), "exit 7\n")

    stdout, stderr, status = invoke_srun('scenarios', extra_env: {'SRUN_FAKE_CRYSTAL_EXIT' => '7'})

    expect(status.exitstatus).to eq(1), stderr
    expect(invocation_lines.map { |line| line.split('|', 2).last }).to eq([
      'run scen/acceptance/fails.scen.cr',
    ])
    expect(report_contents).to include('FAIL: scen/acceptance/fails.scen.cr')
    expect(report_contents).to include('exit code: 7')
    expect(stdout).to include('srun scenarios finished: 0 passed, 1 failed')
  end

  it 'fails clearly and still writes a report when no scenarios are found' do
    Dir.mkdir(File.join(@project, 'scen'))

    stdout, stderr, status = invoke_srun('scenarios')

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include('no scenarios found matching scen/**/*.scen.cr')
    expect(report_contents).to include('No targets found matching scen/**/*.scen.cr.')
    expect(stdout).to include('No targets were discovered.')
    expect(invocation_lines).to be_empty
  end

  it 'rejects unknown subcommands and invalid timeout values' do
    _stdout, stderr, status = invoke_srun('unknown')
    expect(status.exitstatus).to eq(2)
    expect(stderr).to include('unexpected arguments: unknown')

    _stdout, stderr, status = invoke_srun('specs', '--timeout', '0')
    expect(status.exitstatus).to eq(2)
    expect(stderr).to include('timeout must be a positive integer')
  end
end
