import argv
import caffeine_lang/compiler
import gleam/dynamic
import gleam/io

/// Version must match gleam.toml
const version = "0.1.4"

fn print_version() -> Nil {
  io.println("caffeine " <> version)
}

fn print_usage() -> Nil {
  io.println("Caffeine SLI/SLO compiler")
  io.println("")
  io.println("Usage:")
  io.println(
    "  caffeine compile <specification_directory> <instantiation_directory> <output_directory>",
  )
  io.println("")
  io.println("Arguments:")
  io.println(
    "  specification_directory   Directory containing specification files",
  )
  io.println(
    "  instantiation_directory   Directory containing instantiation files",
  )
  io.println("  output_directory          Directory to output compiled files")
}

fn handle_args() -> Nil {
  let args = argv.load().arguments

  case args {
    ["compile", spec_dir, inst_dir, output_dir] -> {
      compiler.compile(spec_dir, inst_dir, output_dir)
    }
    ["compile"] -> {
      io.println_error("Error: compile command requires 3 arguments")
      print_usage()
    }
    ["compile", ..] -> {
      io.println_error("Error: compile command requires exactly 3 arguments")
      print_usage()
    }
    ["--help"] | ["-h"] | [] -> {
      print_usage()
    }
    ["--version"] | ["-V"] -> {
      print_version()
    }
    _ -> {
      io.println_error("Error: unknown command")
      print_usage()
    }
  }
}

// Entry point for Erlang escript
pub fn run(_args: dynamic.Dynamic) -> Nil {
  handle_args()
}

pub fn main() -> Nil {
  handle_args()
}
