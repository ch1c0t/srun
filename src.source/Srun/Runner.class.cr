# Backwards-compatible name for the original per-file spec runner.
@runner : SpecsRunner

def initialize(timeout_seconds : Int32 = DEFAULT_TIMEOUT_SECONDS)
  @runner = SpecsRunner.new(timeout_seconds)
end

def run : Int32
  @runner.run
end
