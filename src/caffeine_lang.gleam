import argv
import caffeine_lang/common/constants
import caffeine_lang/compiler
import gleam/io
import gleam/option.{type Option}
import gleam/result
import gleam/string
import simplifile

// ==== CLI Helpers ===
@external(erlang, "erlang", "halt")
@external(javascript, "./caffeine_lang_ffi.mjs", "halt")
fn halt(code: Int) -> Nil

fn result_to_exit_code(res: Result(Nil, String)) -> Int {
  case res {
    Ok(_) -> constants.exit_success
    Error(msg) -> {
      io.println(msg)
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
    ["compile", blueprint_file, expectations_dir, output_file] ->
      compile(blueprint_file, expectations_dir, option.Some(output_file))
    ["compile", blueprint_file, expectations_dir] ->
      compile(blueprint_file, expectations_dir, option.None)
    ["--help"] | ["-h"] -> {
      print_usage()
      constants.exit_success
    }
    ["--version"] | ["-V"] -> {
      print_version()
      constants.exit_success
    }
    [] -> {
      print_usage()
      constants.exit_success
    }
    _ -> {
      io.println("Error: Invalid arguments")
      io.println("")
      print_usage()
      constants.exit_failure
    }
  }
}

fn compile(
  blueprint_file: String,
  expectations_dir: String,
  output_path: Option(String),
) -> Int {
  {
    use output <- result.try(
      compiler.compile(blueprint_file, expectations_dir)
      |> result.map_error(fn(err) { "Compilation error: " <> err }),
    )

    case output_path {
      option.None -> {
        io.println(output)
        Ok(Nil)
      }
      option.Some(path) -> {
        let output_file = case simplifile.is_directory(path) {
          Ok(True) -> path <> "/main.tf"
          _ -> path
        }
        simplifile.write(output_file, output)
        |> result.map(fn(_) {
          io.println("Successfully compiled to " <> output_file)
        })
        |> result.map_error(fn(err) {
          "Error writing output file: " <> string.inspect(err)
        })
      }
    }
  }
  |> result_to_exit_code
}

fn print_usage() {
  io.println("caffeine " <> constants.version)
  io.println(
    "A compiler for generating reliability artifacts from service expectation definitions.",
  )
  io.println("")
  io.println("USAGE:")
  io.println(
    "    caffeine compile <blueprint_file> <expectations_directory> [output_file]",
  )
  io.println("")
  io.println("ARGUMENTS:")
  io.println(
    "    [output_file]    Output file path or directory (prints to stdout if omitted)",
  )
  io.println("")
  io.println("OPTIONS:")
  io.println("    -h, --help       Print help information")
  io.println("    -V, --version    Print version information")
}

fn print_version() {
  io.println("caffeine " <> constants.version)
}
