import caffeine_lang/common/errors.{type CompilationError}
import caffeine_lang/frontend/pipeline
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
/// expectations directory. Furthermore note that we will ignore non-.caffeine files within
/// an org's team's expectation directory and incorrectly placed .caffeine files will also
/// be ignored.
///
/// ASSUMPTIONS:
///   * specific known directories for expectations and blueprints
///   * no mixed type files
///   * all files are `.caffeine`
@internal
pub fn link(
  blueprint_file_path: String,
  expectations_directory: String,
) -> Result(List(IntermediateRepresentation), CompilationError) {
  use expectation_files <- result.try(file_discovery.get_caffeine_files(
    expectations_directory,
  ))

  use artifacts <- result.try(artifacts.parse_standard_library())

  // Compile blueprints .caffeine file to JSON, then parse
  use blueprints_json <- result.try(pipeline.compile_blueprints_file(
    blueprint_file_path,
  ))
  use blueprints <- result.try(blueprints.parse_from_json_string(
    blueprints_json,
    artifacts,
  ))

  use expectations_with_paths <- result.try(parse_expectation_files(
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
    // Compile expects .caffeine file to JSON, then parse
    pipeline.compile_expects_file(file_path)
    |> result.try(fn(json) {
      expectations.parse_from_json_string(json, blueprints)
    })
    |> result.map(fn(exps) { #(exps, file_path) })
  })
  |> result.all()
}
