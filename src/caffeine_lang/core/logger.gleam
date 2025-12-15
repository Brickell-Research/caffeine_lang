import gleam/io

pub type LogLevel {
  Verbose
  Minimal
}

pub fn log(log_level: LogLevel, message: String) {
  case log_level {
    Verbose -> io.println(message)
    Minimal -> Nil
  }
}
