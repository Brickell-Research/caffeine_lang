import caffeine_lang/common/errors.{type CompilationError}
import caffeine_lang/common/helpers.{result_try}
import caffeine_lang/middle_end/semantic_analyzer.{
  type IntermediateRepresentation,
}
import caffeine_lang/parser/artifacts
import caffeine_lang/parser/blueprints
import caffeine_lang/parser/expectations
import caffeine_lang/parser/file_discovery
import caffeine_lang/parser/ir_builder
import gleam/list
import gleam/result

/// Link will fetch, then parse all configuration files, combining them into one single
/// list of intermediate representation objects. In the future how we fetch these files will
/// change to enable fetching from remote locations, via git, etc. but for now we
/// just support standard library artifacts, a single blueprint file, and a single
/// expectations directory. Furthermore note that we will ignore non-json files within
/// an org's team's expectation directory and incorrectly placed json files will also
/// be ignored.
///
/// ASSUMPTIONS:
///   * specific known directories for expectations and blueprints
///   * no mixed type files
///   * all files are `.json`
pub fn link(
  blueprint_file_path: String,
  expectations_directory: String,
) -> Result(List(IntermediateRepresentation), CompilationError) {
  use expectation_files <- result_try(file_discovery.get_json_files(
    expectations_directory,
  ))

  use artifacts <- result_try(artifacts.parse_standard_library())
  use blueprints <- result_try(blueprints.parse_from_json_file(
    blueprint_file_path,
    artifacts,
  ))
  use expectations_with_paths <- result_try(parse_expectation_files(
    expectation_files,
    blueprints,
  ))

  Ok(ir_builder.build_all(expectations_with_paths))
}

fn parse_expectation_files(
  files: List(String),
  blueprints: List(blueprints.Blueprint),
) {
  files
  |> list.map(fn(file_path) {
    expectations.parse_from_json_file(file_path, blueprints)
    |> result.map(fn(exps) { #(exps, file_path) })
  })
  |> result.all()
}
