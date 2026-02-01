import gleam/io

/// Defines the verbosity level for logging output.
pub type LogLevel {
  Verbose
  Minimal
}

/// Logs a message at the specified log level.
@internal
pub fn log(log_level: LogLevel, message: String) {
  case log_level {
    Verbose -> io.println(message)
    Minimal -> Nil
  }
}

/// Logs a warning message to stderr. Always prints regardless of log level.
@internal
pub fn warn(message: String) {
  io.println_error("warning: " <> message)
}
