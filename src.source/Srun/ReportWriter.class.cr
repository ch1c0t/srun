def write(
  run_directory : RunDirectory,
  mode : String,
  target_label : String,
  target_glob : String,
  timeout_seconds : Int32,
  started_at : Time,
  targets : Array(String),
  results : Array(TargetResult),
  elapsed_seconds : Float64
) : Nil
  File.write(
    run_directory.report_path,
    report_lines(
      run_directory,
      mode,
      target_label,
      target_glob,
      timeout_seconds,
      started_at,
      targets,
      results,
      elapsed_seconds
    ).join("\n") + "\n"
  )
end

def print_summary(
  run_directory : RunDirectory,
  mode : String,
  targets : Array(String),
  results : Array(TargetResult),
  elapsed_seconds : Float64
) : Nil
  passed = results.count { |result| result.outcome == "PASS" }
  failed = results.size - passed

  puts
  puts "srun #{mode} finished: #{passed} passed, #{failed} failed, #{elapsed_seconds.round(2)}s"
  puts "Report: #{run_directory.report_path}"
  puts "Logs:   #{run_directory.root_dir}"
  puts "No targets were discovered." if targets.empty?
end

private def report_lines(
  run_directory : RunDirectory,
  mode : String,
  target_label : String,
  target_glob : String,
  timeout_seconds : Int32,
  started_at : Time,
  targets : Array(String),
  results : Array(TargetResult),
  elapsed_seconds : Float64
) : Array(String)
  passed = results.count { |result| result.outcome == "PASS" }
  failed = results.size - passed
  completed_targets = results.map(&.target)

  lines = [] of String
  lines << "srun report"
  lines << "==========="
  lines << "Mode: #{mode}"
  lines << "Run directory: #{run_directory.root_dir}"
  lines << "Working directory: #{Dir.current}"
  lines << "Started at: #{started_at.to_s("%Y-%m-%d %H:%M:%S")} (Unix time #{started_at.to_unix})"
  lines << "Target glob: #{target_glob}"
  lines << "Execution: each #{target_label.downcase} runs in its own process"
  lines << "Per-target timeout: #{timeout_seconds}s (TERM, then KILL after #{KILL_GRACE_SECONDS}s)"
  lines << "Discovered: #{targets.size}"
  lines << "Completed: #{results.size}/#{targets.size}"
  lines << "Passed: #{passed}"
  lines << "Failed: #{failed}"
  lines << "Elapsed: #{elapsed_seconds.round(2)}s"
  lines << ""
  lines << "#{target_label} results"
  lines << "#{"-" * (target_label.size + 8)}"

  if targets.empty?
    lines << "No targets found matching #{target_glob}."
  elsif results.empty?
    lines << "(No targets completed yet.)"
  else
    results.each do |result|
      lines.concat(result_lines(result, target_label, timeout_seconds, run_directory))
    end
  end

  pending = targets.reject { |target| completed_targets.includes?(target) }
  unless pending.empty?
    lines << ""
    lines << "Not yet run"
    lines << "-----------"
    pending.each { |target| lines << target }
  end

  lines
end

private def result_lines(
  result : TargetResult,
  target_label : String,
  timeout_seconds : Int32,
  run_directory : RunDirectory
) : Array(String)
  lines = [] of String
  lines << "#{result.outcome}: #{result.target}"
  lines << "  elapsed: #{result.elapsed_seconds.round(2)}s"
  lines << "  exit code: #{result.exit_code || "unavailable"}"

  case result.outcome
  when "TIMEOUT"
    lines << "  reason: exceeded the #{timeout_seconds}s timeout; timeout sent TERM and escalated to KILL if needed."
  when "FAIL"
    lines << "  reason: crystal #{target_label == "Scenario" ? "run" : "spec"} exited unsuccessfully (exit code #{result.exit_code})."
  when "RUNNER ERROR"
    lines << "  reason: srun could not start the timeout/crystal process."
  end

  lines << "  full output: #{File.join(run_directory.root_dir, result.log_path)}"
  unless result.excerpt.empty?
    lines << "  last output lines:"
    result.excerpt.lines.each { |line| lines << "    #{line}" }
  end
  lines << ""
  lines
end
