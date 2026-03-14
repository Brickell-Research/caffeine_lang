import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/frontend/pipeline
import caffeine_lang/linker/artifacts.{type ParamInfo}
import caffeine_lang/linker/expectations
import caffeine_lang/linker/ir.{type IntermediateRepresentation, type Linked}
import caffeine_lang/linker/ir_builder
import caffeine_lang/linker/measurements
import caffeine_lang/source_file.{
  type ExpectationSource, type SourceFile, type VendorMeasurementSource,
}
import gleam/dict
import gleam/list
import gleam/result

/// Links measurement sources and expectation sources into intermediate representations.
/// Each measurement source is paired with a vendor derived from its filename.
/// All file reading happens before this function is called — it operates purely
/// on in-memory source content.
@internal
pub fn link(
  measurements: List(VendorMeasurementSource),
  expectation_sources: List(SourceFile(ExpectationSource)),
  slo_params slo_params: dict.Dict(String, ParamInfo),
) -> Result(List(IntermediateRepresentation(Linked)), CompilationError) {
  let reserved_labels = ir_builder.reserved_labels(slo_params)

  // Compile each vendor measurement source and pair measurements with their vendor.
  use compiled_pairs <- result.try(
    measurements
    |> list.map(fn(vbs) {
      pipeline.compile_measurements(vbs.source)
      |> result.map(fn(raw_bps) { #(raw_bps, vbs.vendor) })
    })
    |> errors.from_results(),
  )

  // Flatten all raw measurements and build vendor lookup.
  let all_raw_measurements =
    compiled_pairs |> list.flat_map(fn(pair) { pair.0 })
  let vendor_lookup =
    compiled_pairs
    |> list.flat_map(fn(pair) {
      let #(raw_bps, v) = pair
      list.map(raw_bps, fn(bp) { #(bp.name, v) })
    })
    |> dict.from_list

  // Validate all measurements together (enforces global uniqueness).
  use validated_measurements <- result.try(measurements.validate_measurements(
    all_raw_measurements,
    slo_params,
  ))

  use expectations_with_paths <- result.try(parse_expectation_sources(
    expectation_sources,
    validated_measurements,
    slo_params,
  ))

  ir_builder.build_all(
    expectations_with_paths,
    reserved_labels:,
    vendor_lookup:,
    slo_params:,
  )
}

fn parse_expectation_sources(
  sources: List(SourceFile(ExpectationSource)),
  validated_measurements: List(
    measurements.Measurement(measurements.MeasurementValidated),
  ),
  slo_params: dict.Dict(String, ParamInfo),
) {
  sources
  |> list.map(fn(source) {
    pipeline.compile_expects(source)
    |> result.try(fn(raw_expectations) {
      expectations.validate_expectations(
        raw_expectations,
        validated_measurements,
        slo_params: slo_params,
        from: source.path,
      )
    })
    |> result.map(fn(exps) { #(exps, source.path) })
  })
  |> errors.from_results()
}
