import caffeine_lang/common/errors.{type CompilationError}
import caffeine_lang/common/source_file.{type SourceFile}
import caffeine_lang/frontend/pipeline
import caffeine_lang/middle_end/semantic_analyzer.{
  type IntermediateRepresentation,
}
import caffeine_lang/parser/artifacts
import caffeine_lang/parser/blueprints
import caffeine_lang/parser/expectations
import caffeine_lang/parser/ir_builder
import gleam/list
import gleam/result

/// Links a blueprint and expectation sources into intermediate representations.
/// All file reading happens before this function is called — it operates purely
/// on in-memory source content.
@internal
pub fn link(
  blueprint: SourceFile,
  expectation_sources: List(SourceFile),
) -> Result(List(IntermediateRepresentation), CompilationError) {
  use artifacts <- result.try(artifacts.parse_standard_library())

  // Compile blueprints .caffeine source to JSON, then parse
  use blueprints_json <- result.try(pipeline.compile_blueprints(blueprint))
  use blueprints <- result.try(blueprints.parse_from_json_string(
    blueprints_json,
    artifacts,
  ))

  use expectations_with_paths <- result.try(parse_expectation_sources(
    expectation_sources,
    blueprints,
  ))

  Ok(ir_builder.build_all(expectations_with_paths))
}

fn parse_expectation_sources(
  sources: List(SourceFile),
  blueprints: List(blueprints.Blueprint),
) {
  sources
  |> list.map(fn(source) {
    pipeline.compile_expects(source)
    |> result.try(fn(json) {
      expectations.parse_from_json_string(json, blueprints)
    })
    |> result.map(fn(exps) { #(exps, source.path) })
  })
  |> result.all()
}
