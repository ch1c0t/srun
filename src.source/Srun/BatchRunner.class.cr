@mode : String
@target_label : String
@target_glob : String
@crystal_subcommand : String
@timeout_seconds : Int32

@process_runner : ProcessRunner
@report_writer : ReportWriter

def initialize(
  @mode : String,
  @target_label : String,
  @target_glob : String,
  @crystal_subcommand : String,
  @timeout_seconds : Int32
)
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

private def execute_targets(
  run_directory : RunDirectory,
  started_at : Time,
  targets : Array(String),
  results : Array(TargetResult),
  monotonic_start : Time::Instant
) : Nil
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

private def update_report(
  run_directory : RunDirectory,
  started_at : Time,
  targets : Array(String),
  results : Array(TargetResult),
  monotonic_start : Time::Instant
) : Nil
  @report_writer.write(
    run_directory,
    @mode,
    @target_label,
    @target_glob,
    @timeout_seconds,
    started_at,
    targets,
    results,
    elapsed_seconds(monotonic_start)
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
