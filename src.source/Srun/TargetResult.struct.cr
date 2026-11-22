getter target : String
getter outcome : String
getter exit_code : Int32?
getter elapsed_seconds : Float64
getter log_path : String
getter excerpt : String

def initialize(
  @target : String,
  @outcome : String,
  @exit_code : Int32?,
  @elapsed_seconds : Float64,
  @log_path : String,
  @excerpt : String
)
end
