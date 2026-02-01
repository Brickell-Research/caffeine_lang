import caffeine_lang/logger.{type LogLevel}

/// Configuration settings for the compilation process.
pub type CompilationConfig {
  CompilationConfig(log_level: LogLevel)
}
