require "file_utils"

module Srun
  DEFAULT_TIMEOUT_SECONDS = 10
  KILL_GRACE_SECONDS = 2
  VERSION = "0.0.0"

  record TargetResult,
    target : String,
    outcome : String,
    exit_code : Int32?,
    elapsed_seconds : Float64,
    log_path : String,
    excerpt : String

  class RunDirectory
    getter root_dir : String
    getter passing_dir : String
    getter failing_dir : String
    getter report_path : String

    def initialize(started_at : Time)
      directory_name = File.basename(Dir.current)
      directory_name = "root" if directory_name.empty?
      timestamp = started_at.to_s("%Y%m%d_%H%M%S")
      base_root_dir = File.join(Dir.current, "#{directory_name}.srun.#{started_at.to_unix}_#{timestamp}")

      @root_dir = create_root_directory(base_root_dir)
      @passing_dir = File.join(@root_dir, "passing")
      @failing_dir = File.join(@root_dir, "failing")
      @report_path = File.join(@root_dir, "report.txt")

      FileUtils.mkdir_p(@passing_dir)
      FileUtils.mkdir_p(@failing_dir)
    end

    private def create_root_directory(base_path : String) : String
      candidate = base_path
      suffix = 2
      loop do
        begin
          Dir.mkdir(candidate)
          return candidate
        rescue ex : File::AlreadyExistsError
          candidate = "#{base_path}.#{suffix}"
          suffix += 1
        end
      end
    end
  end

  class ProcessRunner
    def initialize(@timeout_seconds : Int32)
      raise ArgumentError.new("timeout must be positive") unless @timeout_seconds > 0
    end

    def run(target : String, crystal_arguments : Array(String), run_directory : RunDirectory) : TargetResult
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

    private def run_command(log_path : String, crystal_arguments : Array(String)) : Int32?
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

    private def move_log(outcome : String, filename : String, failing_path : String, run_directory : RunDirectory) : String
      if outcome == "PASS"
        File.rename(failing_path, File.join(run_directory.passing_dir, filename))
        File.join("passing", filename)
      else
        File.join("failing", filename)
      end
    end
  end

  class ReportWriter
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
        report_lines(run_directory, mode, target_label, target_glob, timeout_seconds, started_at, targets, results, elapsed_seconds).join("\n") + "\n"
      )
    end

    def print_summary(run_directory : RunDirectory, mode : String, targets : Array(String), results : Array(TargetResult), elapsed_seconds : Float64) : Nil
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
      lines << "-" * (target_label.size + 8)

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

    private def result_lines(result : TargetResult, target_label : String, timeout_seconds : Int32, run_directory : RunDirectory) : Array(String)
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
  end

  class BatchRunner
    @mode : String
    @target_label : String
    @target_glob : String
    @crystal_subcommand : String
    @timeout_seconds : Int32
    @process_runner : ProcessRunner
    @report_writer : ReportWriter

    def initialize(@mode : String, @target_label : String, @target_glob : String, @crystal_subcommand : String, @timeout_seconds : Int32)
      raise ArgumentError.new("timeout must be positive") unless @timeout_seconds > 0
      @process_runner = ProcessRunner.new(@timeout_seconds)
      @report_writer = ReportWriter.new
    end

    def run : Int32
      started_at = Time.local
      monotonic_start = Time.instant
      targets = discover_targets
      results = [] of TargetResult
      run_directory = RunDirectory.new(started_at)

      update_report(run_directory, started_at, targets, results, monotonic_start)
      report_empty_targets(targets)
      execute_targets(run_directory, started_at, targets, results, monotonic_start)
      update_report(run_directory, started_at, targets, results, monotonic_start)

      elapsed = elapsed_seconds(monotonic_start)
      @report_writer.print_summary(run_directory, @mode, targets, results, elapsed)
      successful?(targets, results) ? 0 : 1
    end

    private def discover_targets : Array(String)
      Dir.glob(@target_glob).sort
    end

    private def execute_targets(run_directory : RunDirectory, started_at : Time, targets : Array(String), results : Array(TargetResult), monotonic_start : Time::Instant) : Nil
      targets.each_with_index do |target, index|
        puts "[#{index + 1}/#{targets.size}] Running #{target} (timeout: #{@timeout_seconds}s)"
        result = @process_runner.run(target, command_arguments(target), run_directory)
        results << result
        puts "  #{result.outcome}: #{target} (#{result.elapsed_seconds.round(2)}s)"
        update_report(run_directory, started_at, targets, results, monotonic_start)
      end
    end

    private def command_arguments(target : String) : Array(String)
      [@crystal_subcommand, target]
    end

    private def update_report(run_directory : RunDirectory, started_at : Time, targets : Array(String), results : Array(TargetResult), monotonic_start : Time::Instant) : Nil
      @report_writer.write(
        run_directory, @mode, @target_label, @target_glob, @timeout_seconds,
        started_at, targets, results, elapsed_seconds(monotonic_start)
      )
    end

    private def elapsed_seconds(monotonic_start : Time::Instant) : Float64
      (Time.instant - monotonic_start).total_seconds
    end

    private def report_empty_targets(targets : Array(String)) : Nil
      return unless targets.empty?
      STDERR.puts "srun: no #{@target_label.downcase}s found matching #{@target_glob}"
    end

    private def successful?(targets : Array(String), results : Array(TargetResult)) : Bool
      !targets.empty? && results.size == targets.size && results.all? { |result| result.outcome == "PASS" }
    end
  end

  class SpecsRunner
    def initialize(timeout_seconds : Int32 = DEFAULT_TIMEOUT_SECONDS)
      @runner = BatchRunner.new("specs", "Spec", "spec/**/*_spec.cr", "spec", timeout_seconds)
    end
    def run : Int32
      @runner.run
    end
  end

  class ScenariosRunner
    def initialize(timeout_seconds : Int32 = DEFAULT_TIMEOUT_SECONDS)
      @runner = BatchRunner.new("scenarios", "Scenario", "scen/**/*.scen.cr", "run", timeout_seconds)
    end
    def run : Int32
      @runner.run
    end
  end

  # Backwards-compatible name for the original per-file spec runner.
  class Runner
    def initialize(timeout_seconds : Int32 = DEFAULT_TIMEOUT_SECONDS)
      @runner = SpecsRunner.new(timeout_seconds)
    end
    def run : Int32
      @runner.run
    end
  end
end
