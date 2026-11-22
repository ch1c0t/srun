getter root_dir : String
getter passing_dir : String
getter failing_dir : String
getter report_path : String

def initialize(started_at : Time)
  directory_name = File.basename(Dir.current)
  directory_name = "root" if directory_name.empty?
  timestamp = started_at.to_s("%Y%m%d_%H%M%S")
  base_root_dir = File.join(
    Dir.current,
    "#{directory_name}.srun.#{started_at.to_unix}_#{timestamp}"
  )

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
