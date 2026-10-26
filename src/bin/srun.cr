require "./srun/*"

VERSION = "0.0.0"

case ARGV.size
when 1
  case ARGV[0]
  when "-v", "version", "--version"
    puts VERSION
    exit
  when "-h", "help", "--help"
    print_help
    exit
  end
end

require "../srun"
require "option_parser"

timeout_seconds = Srun::DEFAULT_TIMEOUT_SECONDS
if env_timeout = ENV["SRUN_TIMEOUT"]?
  parsed_timeout = env_timeout.to_i? || 0
  unless parsed_timeout > 0
    STDERR.puts "srun: SRUN_TIMEOUT must be a positive integer number of seconds"
    exit 2
  end
  timeout_seconds = parsed_timeout
end

OptionParser.parse do |parser|
  parser.banner = "Usage: srun [--timeout SECONDS]"
  parser.on("-t SECONDS", "--timeout=SECONDS", "Timeout for each spec (default: #{timeout_seconds}s)") do |value|
    parsed_timeout = value.to_i? || 0
    unless parsed_timeout > 0
      STDERR.puts "srun: timeout must be a positive integer number of seconds"
      exit 2
    end
    timeout_seconds = parsed_timeout
  end
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
end

unless ARGV.empty?
  STDERR.puts "srun: unexpected arguments: #{ARGV.join(" ")}"
  STDERR.puts "Try 'srun --help' for usage."
  exit 2
end

exit Srun::Runner.new(timeout_seconds).run
