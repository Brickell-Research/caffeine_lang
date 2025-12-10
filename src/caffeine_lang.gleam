import argv
import caffeine_lang/compiler
import gleam/io
import gleam/string
import simplifile

const version = "0.2.1"

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
      compile(blueprint_file, expectations_dir, output_file)
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
  output_path: String,
) {
  // If output_path is a directory, append main.tf
  let output_file = case simplifile.is_directory(output_path) {
    Ok(True) -> output_path <> "/main.tf"
    _ -> output_path
  }

  case compiler.compile(blueprint_file, expectations_dir) {
    Ok(output) -> {
      case simplifile.write(output_file, output) {
        Ok(_) -> io.println("Successfully compiled to " <> output_file)
        Error(err) ->
          io.println("Error writing output file: " <> string.inspect(err))
      }
    }
    Error(err) -> io.println("Compilation error: " <> err)
  }
}

fn print_usage() {
  io.println("caffeine " <> version)
  io.println(
    "A compiler for generating reliability artifacts from service expectation definitions.",
  )
  io.println("")
  io.println("USAGE:")
  io.println(
    "    caffeine compile <blueprint_file> <expectations_directory> <output_file>",
  )
  io.println("")
  io.println("OPTIONS:")
  io.println("    -h, --help       Print help information")
  io.println("    -V, --version    Print version information")
}

fn print_version() {
  io.println("caffeine " <> version)
}
