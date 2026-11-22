def initialize(timeout_seconds : Int32 = DEFAULT_TIMEOUT_SECONDS)
  @runner = BatchRunner.new(
    "specs",
    "Spec",
    "spec/**/*_spec.cr",
    "spec",
    timeout_seconds
  )
end

def run : Int32
  @runner.run
end
