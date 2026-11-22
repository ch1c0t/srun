require "../srun"
require "option_parser"

arguments = ARGV.dup

case arguments.first?
when "help"
  print_help
  exit 0
when "version"
  puts Srun::VERSION
  exit 0
end

mode = case arguments.first?
       when "specs"
         arguments.shift
         "specs"
       when "scenarios"
         arguments.shift
         "scenarios"
       else
         Dir.exists?("scen") ? "scenarios" : "specs"
       end

timeout_seconds = Srun::DEFAULT_TIMEOUT_SECONDS
if env_timeout = ENV["SRUN_TIMEOUT"]?
  parsed_timeout = env_timeout.to_i? || 0
  unless parsed_timeout > 0
    STDERR.puts "srun: SRUN_TIMEOUT must be a positive integer number of seconds"
    exit 2
  end
  timeout_seconds = parsed_timeout
end

OptionParser.parse(arguments) do |parser|
  parser.banner = "Usage: srun [specs|scenarios] [--timeout SECONDS]"
  parser.on("-t SECONDS", "--timeout=SECONDS", "Timeout for each target (default: #{timeout_seconds}s)") do |value|
    parsed_timeout = value.to_i? || 0
    unless parsed_timeout > 0
      STDERR.puts "srun: timeout must be a positive integer number of seconds"
      exit 2
    end
    timeout_seconds = parsed_timeout
  end
  parser.on("-h", "--help", "Show this help") do
    print_help
    exit 0
  end
  parser.on("-v", "--version", "Show the version") do
    puts Srun::VERSION
    exit 0
  end
end

unless arguments.empty?
  STDERR.puts "srun: unexpected arguments: #{arguments.join(" ")}"
  STDERR.puts "Try 'srun --help' for usage."
  exit 2
end

runner = case mode
         when "scenarios"
           Srun::ScenariosRunner.new(timeout_seconds)
         else
           Srun::SpecsRunner.new(timeout_seconds)
         end

exit runner.run
