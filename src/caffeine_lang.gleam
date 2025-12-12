import argv
import caffeine_lang/common/constants
import caffeine_lang/compiler.{type LogLevel, Minimal, Verbose}
import gleam/io
import gleam/option.{type Option}
import gleam/result
import gleam/string
import simplifile

// ==== CLI Helpers ===
@external(erlang, "erlang", "halt")
@external(javascript, "./caffeine_lang_ffi.mjs", "halt")
fn halt(code: Int) -> Nil

fn log(log_level: LogLevel, message: String) {
  case log_level {
    Verbose -> io.println(message)
    Minimal -> Nil
  }
}

fn result_to_exit_code(
  res: Result(Nil, String),
  log_level: LogLevel,
) -> Int {
  case res {
    Ok(_) -> constants.exit_success
    Error(msg) -> {
      log(log_level, msg)
      constants.exit_failure
    }
  }
}

// ==== Main ====
pub fn main() {
  let exit_code = handle_args(argv.load().arguments)
  case exit_code {
    code if code == constants.exit_success -> Nil
    _ -> halt(exit_code)
  }
}

/// Entry point for Erlang escript compatibility
pub fn run(args: List(String)) -> Int {
  handle_args(args)
}

fn handle_args(args: List(String)) -> Int {
  case args {
    ["compile", "--quiet", blueprint_file, expectations_dir, output_file] ->
      compile(
        blueprint_file,
        expectations_dir,
        option.Some(output_file),
        Minimal,
      )
    ["compile", "--quiet", blueprint_file, expectations_dir] ->
      compile(blueprint_file, expectations_dir, option.None, Minimal)
    ["compile", blueprint_file, expectations_dir, output_file] ->
      compile(
        blueprint_file,
        expectations_dir,
        option.Some(output_file),
        Verbose,
      )
    ["compile", blueprint_file, expectations_dir] ->
      compile(blueprint_file, expectations_dir, option.None, Verbose)
    ["--help"] | ["-h"] -> {
      print_usage(Verbose)
      constants.exit_success
    }
    ["--version"] | ["-V"] -> {
      print_version(Verbose)
      constants.exit_success
    }
    ["--quiet", "--help"]
    | ["--quiet", "-h"]
    | ["--help", "--quiet"]
    | ["-h", "--quiet"]
    -> {
      print_usage(Minimal)
      constants.exit_success
    }
    ["--quiet", "--version"]
    | ["--quiet", "-V"]
    | ["--version", "--quiet"]
    | ["-V", "--quiet"]
    -> {
      print_version(Minimal)
      constants.exit_success
    }
    ["--quiet"] -> {
      print_usage(Minimal)
      constants.exit_success
    }
    [] -> {
      print_usage(Verbose)
      constants.exit_success
    }
    _ -> {
      log(Verbose, "Error: Invalid arguments")
      log(Verbose, "")
      print_usage(Verbose)
      constants.exit_failure
    }
  }
}

fn compile(
  blueprint_file: String,
  expectations_dir: String,
  output_path: Option(String),
  log_level: LogLevel,
) -> Int {
  let config = compiler.CompilationConfig(log_level: log_level)
  {
    use output <- result.try(
      compiler.compile(blueprint_file, expectations_dir, config)
      |> result.map_error(fn(err) { "Compilation error: " <> err }),
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
  |> result_to_exit_code(log_level)
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
