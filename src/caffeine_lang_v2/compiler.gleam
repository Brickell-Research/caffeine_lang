import caffeine_lang_v2/generator/datadog
import caffeine_lang_v2/middle_end/semantic_analyzer
import caffeine_lang_v2/parser/linker
import gleam/result

// TODO: have an actual error type
pub fn compile(
  blueprint_file_path: String,
  expectations_directory: String,
) -> Result(String, String) {
  use irs <- result.try(
    case linker.link(blueprint_file_path, expectations_directory) {
      Error(err) -> Error(err.msg)
      Ok(irs) -> Ok(irs)
    },
  )

  use resolved_irs <- result.try(
    case semantic_analyzer.resolve_intermediate_representations(irs) {
      Error(err) -> Error(err.msg)
      Ok(resolved_irs) -> Ok(resolved_irs)
    },
  )

  Ok(datadog.generate_terraform(resolved_irs))
}
