require 'open3'
require 'tmpdir'
require 'fileutils'

SRUN_BINARY = File.expand_path('../bin/srun', __dir__)

def run_srun(*arguments, chdir:, env: {})
  Open3.capture3(env, SRUN_BINARY, *arguments, chdir: chdir)
end

def install_fake_crystal(project_directory)
  fake_bin = File.join(project_directory, 'fake-bin')
  FileUtils.mkdir_p(fake_bin)
  executable = File.join(fake_bin, 'crystal')
  File.write(executable, <<~SH)
    #!/bin/sh
    printf '%s|%s\n' "$$" "$*" >> "$SRUN_FAKE_CRYSTAL_LOG"
    printf 'fake crystal: %s\n' "$*"
    if [ -n "${SRUN_FAKE_CRYSTAL_SLEEP:-}" ]; then
      sleep "$SRUN_FAKE_CRYSTAL_SLEEP"
    fi
    exit "${SRUN_FAKE_CRYSTAL_EXIT:-0}"
  SH
  File.chmod(0o755, executable)

  {
    'PATH' => "#{fake_bin}:#{ENV.fetch('PATH', '')}",
    'SRUN_FAKE_CRYSTAL_LOG' => File.join(project_directory, 'crystal-invocations.log'),
    'SRUN_TIMEOUT' => nil,
    'SRUN_FAKE_CRYSTAL_EXIT' => nil,
    'SRUN_FAKE_CRYSTAL_SLEEP' => nil,
  }
end

def run_directory(project_directory)
  prefix = "#{File.basename(project_directory)}.srun."
  candidate = Dir.children(project_directory)
    .select { |name| name.start_with?(prefix) }
    .max
  raise "srun did not create a run directory in #{project_directory}" unless candidate

  File.join(project_directory, candidate)
end
