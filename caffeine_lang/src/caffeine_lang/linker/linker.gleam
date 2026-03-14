import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/frontend/pipeline
import caffeine_lang/linker/artifacts.{type Artifact}
import caffeine_lang/linker/blueprints
import caffeine_lang/linker/expectations
import caffeine_lang/linker/ir.{type IntermediateRepresentation, type Linked}
import caffeine_lang/linker/ir_builder
import caffeine_lang/source_file.{
  type ExpectationSource, type SourceFile, type VendorBlueprintSource,
}
import gleam/dict
import gleam/list
import gleam/result

/// Links blueprint sources and expectation sources into intermediate representations.
/// Each blueprint source is paired with a vendor derived from its filename.
/// All file reading happens before this function is called — it operates purely
/// on in-memory source content.
@internal
pub fn link(
  blueprints: List(VendorBlueprintSource),
  expectation_sources: List(SourceFile(ExpectationSource)),
  artifacts artifacts: List(Artifact),
) -> Result(List(IntermediateRepresentation(Linked)), CompilationError) {
  let reserved_labels = ir_builder.reserved_labels_from_artifacts(artifacts)

  // Compile each vendor blueprint source and pair blueprints with their vendor.
  use compiled_pairs <- result.try(
    blueprints
    |> list.map(fn(vbs) {
      pipeline.compile_blueprints(vbs.source)
      |> result.map(fn(raw_bps) { #(raw_bps, vbs.vendor) })
    })
    |> errors.from_results(),
  )

  // Flatten all raw blueprints and build vendor lookup.
  let all_raw_blueprints = compiled_pairs |> list.flat_map(fn(pair) { pair.0 })
  let vendor_lookup =
    compiled_pairs
    |> list.flat_map(fn(pair) {
      let #(raw_bps, v) = pair
      list.map(raw_bps, fn(bp) { #(bp.name, v) })
    })
    |> dict.from_list

  // Validate all blueprints together (enforces global uniqueness).
  use validated_blueprints <- result.try(blueprints.validate_blueprints(
    all_raw_blueprints,
    artifacts,
  ))

  use expectations_with_paths <- result.try(parse_expectation_sources(
    expectation_sources,
    validated_blueprints,
  ))

  ir_builder.build_all(
    expectations_with_paths,
    reserved_labels:,
    vendor_lookup:,
  )
}

fn parse_expectation_sources(
  sources: List(SourceFile(ExpectationSource)),
  validated_blueprints: List(
    blueprints.Blueprint(blueprints.BlueprintValidated),
  ),
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
