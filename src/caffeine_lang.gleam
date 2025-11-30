import argv
import caffeine_lang_v2/generator
import caffeine_lang_v2/linker
import caffeine_lang_v2/semantic_analyzer

import gleam/result

pub fn handle_arguments(args: List(String)) -> Result(Bool, String) {
  case args {
    [] -> Error("No arguments")
    [first, second] -> compile(first, second)
    _ -> Error("Expects only two arguments")
  }
}

pub fn compile(
  blueprint_file_path: String,
  expectations_directory: String,
) -> Result(Bool, String) {
  use abstract_syntax_tree <- result.try(linker.link(
    blueprint_file_path,
    expectations_directory,
  ))

  use _ <- result.try(semantic_analyzer.perform(abstract_syntax_tree))

  generator.generate(abstract_syntax_tree)

  Ok(True)
}

pub fn main() {
  argv.load().arguments
  |> handle_arguments
}
