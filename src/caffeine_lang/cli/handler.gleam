import caffeine_lang/cli/exit_status_codes.{type ExitStatusCodes}
import caffeine_lang/common/constants
import caffeine_lang/core/compilation_configuration
import caffeine_lang/core/compiler
import caffeine_lang/core/logger.{type LogLevel}
import gleam/io
import gleam/option.{type Option}
import gleam/result
import gleam/string
import simplifile

/// Handles CLI arguments and dispatches to appropriate commands.
@internal
pub fn handle_args(args: List(String)) -> ExitStatusCodes {
  case args {
    ["compile", "--quiet", blueprint_file, expectations_dir, output_file] ->
      compile(
        blueprint_file,
        expectations_dir,
        option.Some(output_file),
        logger.Minimal,
      )
    ["compile", "--quiet", blueprint_file, expectations_dir] ->
      compile(blueprint_file, expectations_dir, option.None, logger.Minimal)
    ["compile", blueprint_file, expectations_dir, output_file] ->
      compile(
        blueprint_file,
        expectations_dir,
        option.Some(output_file),
        logger.Verbose,
      )
    ["compile", blueprint_file, expectations_dir] ->
      compile(blueprint_file, expectations_dir, option.None, logger.Verbose)
    ["--help"] | ["-h"] -> {
      print_usage(logger.Verbose)
      exit_status_codes.Success
    }
    ["--version"] | ["-V"] -> {
      print_version(logger.Verbose)
      exit_status_codes.Success
    }
    ["--quiet", "--help"]
    | ["--quiet", "-h"]
    | ["--help", "--quiet"]
    | ["-h", "--quiet"] -> {
      print_usage(logger.Minimal)
      exit_status_codes.Success
    }
    ["--quiet", "--version"]
    | ["--quiet", "-V"]
    | ["--version", "--quiet"]
    | ["-V", "--quiet"] -> {
      print_version(logger.Minimal)
      exit_status_codes.Success
    }
    ["--quiet"] -> {
      print_usage(logger.Minimal)
      exit_status_codes.Success
    }
    [] -> {
      print_usage(logger.Verbose)
      exit_status_codes.Success
    }
    _ -> {
      log(logger.Verbose, "Error: Invalid arguments")
      log(logger.Verbose, "")
      print_usage(logger.Verbose)
      exit_status_codes.Failure
    }
  }
}

fn compile(
  blueprint_file: String,
  expectations_dir: String,
  output_path: Option(String),
  log_level: LogLevel,
) -> ExitStatusCodes {
  let config = compilation_configuration.CompilationConfig(log_level: log_level)
  {
    use output <- result.try(
      compiler.compile(blueprint_file, expectations_dir, config)
      |> result.map_error(fn(err) { "Compilation error: " <> err.msg }),
    )

    case output_path {
      option.None -> {
        log(log_level, output)
        Ok(Nil)
      }
      option.Some(path) -> {
        let output_file = case simplifile.is_directory(path) {
          Ok(True) -> path <> "/main.tf"
          _ -> path
        }
        simplifile.write(output_file, output)
        |> result.map(fn(_) {
          log(log_level, "Successfully compiled to " <> output_file)
        })
        |> result.map_error(fn(err) {
          "Error writing output file: " <> string.inspect(err)
        })
      }
    }
  }
  |> result_to_exit_status(log_level)
}

fn print_usage(log_level: LogLevel) {
  log(log_level, "caffeine " <> constants.version)
  log(
    log_level,
    "A compiler for generating reliability artifacts from service expectation definitions.",
  )
  log(log_level, "")
  log(log_level, "USAGE:")
  log(
    log_level,
    "    caffeine compile [--quiet] <blueprint_file> <expectations_directory> [output_file]",
  )
  log(log_level, "")
  log(log_level, "ARGUMENTS:")
  log(
    log_level,
    "    [output_file]    Output file path or directory (prints to stdout if omitted)",
  )
  log(log_level, "")
  log(log_level, "OPTIONS:")
  log(log_level, "    --quiet          Suppress compilation progress output")
  log(log_level, "    -h, --help       Print help information")
  log(log_level, "    -V, --version    Print version information")
}

fn print_version(log_level: LogLevel) {
  log(log_level, "caffeine " <> constants.version)
}

fn log(log_level: LogLevel, message: String) {
  case log_level {
    logger.Verbose -> io.println(message)
    logger.Minimal -> Nil
  }
}

fn result_to_exit_status(
  res: Result(Nil, String),
  log_level: LogLevel,
) -> ExitStatusCodes {
  case res {
    Ok(_) -> exit_status_codes.Success
    Error(msg) -> {
      log(log_level, msg)
      exit_status_codes.Failure
    }
  }
}
