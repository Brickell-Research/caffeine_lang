import argv
import caffeine_lang/common/constants
import caffeine_lang/compiler
import gleam/io
import gleam/option.{type Option}
import gleam/string
import simplifile

pub fn main() {
  handle_args(argv.load().arguments)
}

/// Entry point for Erlang escript compatibility
pub fn run(args: List(String)) {
  handle_args(args)
}

fn handle_args(args: List(String)) {
  case args {
    ["compile", blueprint_file, expectations_dir, output_file] ->
      compile(blueprint_file, expectations_dir, option.Some(output_file))
    ["compile", blueprint_file, expectations_dir] ->
      compile(blueprint_file, expectations_dir, option.None)
    ["--help"] | ["-h"] -> print_usage()
    ["--version"] | ["-V"] -> print_version()
    [] -> print_usage()
    _ -> {
      io.println("Error: Invalid arguments")
      io.println("")
      print_usage()
    }
  }
}

fn compile(
  blueprint_file: String,
  expectations_dir: String,
  output_path: Option(String),
) {
  case compiler.compile(blueprint_file, expectations_dir) {
    Ok(output) -> {
      case output_path {
        // Print to stdout if no output file specified
        option.None -> io.println(output)
        // Otherwise write to file
        option.Some(path) -> {
          // If output_path is a directory, append main.tf
          let output_file = case simplifile.is_directory(path) {
            Ok(True) -> path <> "/main.tf"
            _ -> path
          }
          case simplifile.write(output_file, output) {
            Ok(_) -> io.println("Successfully compiled to " <> output_file)
            Error(err) ->
              io.println("Error writing output file: " <> string.inspect(err))
          }
        }
      }
    }
    Error(err) -> io.println("Compilation error: " <> err)
  }
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
