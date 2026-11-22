def initialize(@timeout_seconds : Int32)
  raise ArgumentError.new("timeout must be positive") unless @timeout_seconds > 0
end

def run(
  target : String,
  crystal_arguments : Array(String),
  run_directory : RunDirectory
) : TargetResult
  filename = "#{target.gsub("/", "__")}.log"
  failing_path = File.join(run_directory.failing_dir, filename)
  started_at = Time.instant
  exit_code = run_command(failing_path, crystal_arguments)

  elapsed = (Time.instant - started_at).total_seconds
  output = File.read(failing_path)
  outcome = classify_outcome(output, exit_code)
  log_path = move_log(outcome, filename, failing_path, run_directory)
  excerpt = outcome == "PASS" ? "" : output.lines.map(&.rstrip).last(12).join("\n")

  TargetResult.new(target, outcome, exit_code, elapsed, log_path, excerpt)
end

private def run_command(
  log_path : String,
  crystal_arguments : Array(String)
) : Int32?
  # GNU timeout starts the test command in a separate process group. This
  # lets a timeout terminate the Crystal process and its child processes.
  File.open(log_path, "w") do |log|
    begin
      status = Process.run(
        "timeout",
        [
          "--verbose",
          "--signal=TERM",
          "--kill-after=#{KILL_GRACE_SECONDS}s",
          "#{@timeout_seconds}s",
          "crystal",
        ] + crystal_arguments,
        output: log,
        error: log
      )
      log.flush
      status.exit_code
    rescue ex
      log.puts
      log.puts("srun could not launch crystal: #{ex.class}: #{ex.message}")
      log.flush
      nil
    end
  end
end

private def classify_outcome(output : String, exit_code : Int32?) : String
  if output.includes?("timeout: sending signal")
    "TIMEOUT"
  elsif exit_code == 0
    "PASS"
  elsif exit_code.nil?
    "RUNNER ERROR"
  else
    "FAIL"
  end
end

private def move_log(
  outcome : String,
  filename : String,
  failing_path : String,
  run_directory : RunDirectory
) : String
  if outcome == "PASS"
    File.rename(failing_path, File.join(run_directory.passing_dir, filename))
    File.join("passing", filename)
  else
    File.join("failing", filename)
  end
end
