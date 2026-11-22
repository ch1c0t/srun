require_relative 'helper'

describe 'cli' do
  it 'prints the command overview' do
    stdout, stderr, status = run_srun('--help', chdir: File.expand_path('..', __dir__))

    expect(status.exitstatus).to eq(0), stderr
    expect(stdout).to start_with('Usage: srun [specs|scenarios]')
    expect(stdout).to include('Run every spec/**/*_spec.cr file')
    expect(stdout).to include('scen/**/*.scen.cr')
  end
end
