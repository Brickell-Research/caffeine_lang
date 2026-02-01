import caffeine_lang/compiler.{type CompilationOutput}
import caffeine_lang/errors
import caffeine_lang/source_file.{type SourceFile}
import gleam/io
import gleam/list
import gleam/result
import gleam_community/ansi

/// Defines the verbosity level for CLI output.
pub type LogLevel {
  Verbose
  Minimal
}

/// Compiles with ANSI progress output around the pure compiler call.
pub fn compile_with_output(
  blueprint: SourceFile,
  expectations: List(SourceFile),
  log_level: LogLevel,
) -> Result(CompilationOutput, errors.CompilationError) {
  log(log_level, "")
  log(log_level, ansi.bold(ansi.cyan("=== CAFFEINE COMPILER ===")))
  log(log_level, "")

  use output <- result.try(case compiler.compile(blueprint, expectations) {
    Ok(output) -> {
      log(log_level, "  " <> ansi.green("✓ Compilation succeeded"))
      Ok(output)
    }
    Error(err) -> {
      log(log_level, "  " <> ansi.red("✗ Compilation failed"))
      Error(err)
    }
  })

  // Print any warnings from the compiler.
  output.warnings
  |> list.each(fn(warning) { io.println_error("warning: " <> warning) })

  log(log_level, "")
  log(log_level, ansi.bold(ansi.green("=== COMPILATION COMPLETE ===")))
  log(log_level, "")

  Ok(output)
}

/// Logs a message at the specified log level.
pub fn log(log_level: LogLevel, message: String) {
  case log_level {
    Verbose -> io.println(message)
    Minimal -> Nil
  }
}
