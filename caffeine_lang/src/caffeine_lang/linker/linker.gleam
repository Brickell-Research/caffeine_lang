import caffeine_lang/analysis/semantic_analyzer.{type IntermediateRepresentation}
import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/frontend/pipeline
import caffeine_lang/linker/blueprints
import caffeine_lang/linker/expectations
import caffeine_lang/linker/ir_builder
import caffeine_lang/source_file.{type SourceFile}
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
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
  let artifacts = stdlib_artifacts.standard_library()

  // Compile blueprints .caffeine source, then validate
  use raw_blueprints <- result.try(pipeline.compile_blueprints(blueprint))
  use validated_blueprints <- result.try(blueprints.validate_blueprints(
    raw_blueprints,
    artifacts,
  ))

  use expectations_with_paths <- result.try(parse_expectation_sources(
    expectation_sources,
    validated_blueprints,
  ))

  Ok(ir_builder.build_all(expectations_with_paths))
}

fn parse_expectation_sources(
  sources: List(SourceFile),
  validated_blueprints: List(blueprints.Blueprint),
) {
  sources
  |> list.map(fn(source) {
    pipeline.compile_expects(source)
    |> result.try(fn(raw_expectations) {
      expectations.validate_expectations(
        raw_expectations,
        validated_blueprints,
        from: source.path,
      )
    })
    |> result.map(fn(exps) { #(exps, source.path) })
  })
  |> errors.from_results()
}
