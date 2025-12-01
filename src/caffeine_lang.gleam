import argv
import caffeine_lang_v2/generator/generator
import caffeine_lang_v2/linker
import caffeine_lang_v2/semantic_analyzer
import gleam/dynamic
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import simplifile

fn get_version() -> String {
  let assert Ok(contents) = simplifile.read("gleam.toml")

  let assert Ok(version_line) =
    contents
    |> string.split("\n")
    |> list.find(fn(line) { string.starts_with(line, "version") })

  let assert Ok(version) =
    version_line
    |> string.split("=")
    |> list.last

  version
  |> string.trim
  |> string.replace("\"", "")
}

fn print_version() -> Nil {
  io.println("caffeine " <> get_version())
}

fn print_usage() -> Nil {
  io.println("Caffeine SLI/SLO compiler v" <> get_version())
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
  io.println("  blueprint_file            Path to the blueprint YAML file")
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
) -> Nil {
  let result = {
    use abstract_syntax_tree <- result.try(linker.link(
      blueprint_file_path,
      expectations_directory,
    ))

    use _ <- result.try(semantic_analyzer.perform(abstract_syntax_tree))

    use generated <- result.try(generator.generate(abstract_syntax_tree))

    // TODO: write generated output to output_directory
    io.println("Generated output to: " <> output_directory)
    io.println(generated)

    Ok(Nil)
  }

  case result {
    Ok(_) -> io.println("Compilation successful!")
    Error(msg) -> io.println_error("Error: " <> msg)
  }
}

fn handle_args() -> Nil {
  let args = argv.load().arguments

  case args {
    ["compile", blueprint_file, expectations_dir, output_dir] -> {
      compile(blueprint_file, expectations_dir, output_dir)
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
