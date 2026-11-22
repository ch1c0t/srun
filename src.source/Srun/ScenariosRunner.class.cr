def initialize(timeout_seconds : Int32 = DEFAULT_TIMEOUT_SECONDS)
  @runner = BatchRunner.new(
    "scenarios",
    "Scenario",
    "scen/**/*.scen.cr",
    "run",
    timeout_seconds
  )
end

def run : Int32
  @runner.run
end
