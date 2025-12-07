import argv
import caffeine_lang_v2/generator/common
import caffeine_lang_v2/generator/generator
import caffeine_lang_v2/linker
import gleam/io
import gleam/result
import simplifile

/// Version must match gleam.toml
const version = "0.2.0"

fn print_version() -> Nil {
  io.println("caffeine " <> version)
}

fn print_usage() -> Nil {
  io.println("Caffeine SLI/SLO compiler v" <> version)
  io.println("")
  io.println("Usage:")
  io.println(
    "  caffeine compile <blueprint_file> <expectations_directory> <output_directory>",
  )
  io.println("")
  io.println("Commands:")
  io.println(
    "  compile    Compile blueprint and expectation files to output directory",
  )
  io.println("")
  io.println("Arguments:")
  io.println("  blueprint_file            Path to the blueprint JSON file")
  io.println(
    "  expectations_directory    Directory containing expectation files",
  )
  io.println("  output_directory          Directory to output compiled files")
  io.println("")
  io.println("Options:")
  io.println("  -h, --help       Print this help message")
  io.println("  -V, --version    Print version information")
}

pub fn compile(
  blueprint_file_path: String,
  expectations_directory: String,
  output_directory: String,
) -> Result(Nil, String) {
  use irs <- result_try(linker.link(blueprint_file_path, expectations_directory))

  use generated <- result_try(
    generator.generate(irs)
    |> result.map_error(common.format_error),
  )

  // Write output to file
  let output_file = output_directory <> "/main.tf"
  use _ <- result_try(
    simplifile.write(output_file, generated)
    |> result.map_error(fn(err) { simplifile.describe_error(err) }),
  )

  io.println("Generated terraform to: " <> output_file)
  Ok(Nil)
}

fn result_try(result: Result(a, e), next: fn(a) -> Result(b, e)) -> Result(b, e) {
  case result {
    Ok(value) -> next(value)
    Error(err) -> Error(err)
  }
}

fn handle_args() -> Nil {
  let args = argv.load().arguments

  case args {
    ["compile", blueprint_file, expectations_dir, output_dir] -> {
      case compile(blueprint_file, expectations_dir, output_dir) {
        Ok(_) -> io.println("Compilation successful!")
        Error(msg) -> io.println_error("Error: " <> msg)
      }
    }
    ["compile"] -> {
      io.println_error("Error: compile command requires 3 arguments")
      io.println_error(
        "Usage: caffeine compile <blueprint_file> <expectations_directory> <output_directory>",
      )
    }
    ["compile", ..] -> {
      io.println_error("Error: compile command requires exactly 3 arguments")
      io.println_error(
        "Usage: caffeine compile <blueprint_file> <expectations_directory> <output_directory>",
      )
    }
    ["-h"] | ["--help"] | ["help"] -> print_usage()
    ["-V"] | ["--version"] | ["version"] -> print_version()
    [] -> print_usage()
    _ -> {
      io.println_error("Unknown command or arguments")
      print_usage()
    }
  }
}

pub fn main() {
  handle_args()
}
