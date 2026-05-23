import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/frontend/ast.{type ExpectationType}
import caffeine_lang/linker/slo_params.{type ParamInfo, params_to_types}
import caffeine_lang/linker/validations
import caffeine_lang/types.{type AcceptedTypes}
import caffeine_lang/value.{type Value}
import gleam/dict
import gleam/list
import gleam/option.{type Option}
import gleam/result

/// Marker type for measurements that have not yet been validated.
pub type Raw

/// Marker type for measurements that have passed validation.
pub type MeasurementValidated

/// A Measurement provides a partial set of inputs to the SLO param schema and
/// declares any additional params the bound Expectation must satisfy.
/// The phantom type parameter `state` tracks whether the measurement is `Raw` or `MeasurementValidated`.
pub type Measurement(state) {
  Measurement(
    name: String,
    params: dict.Dict(String, AcceptedTypes),
    inputs: dict.Dict(String, Value),
    /// Resolved type constraints on `value:` extractions for any external
    /// indicators in this measurement's `Provides { indicators: { ... } }`
    /// block. Keyed by indicator name (same key used in `inputs.indicators`).
    /// Empty when no external indicators have value extraction. Populated by
    /// lowering because the type info would otherwise have nowhere to live —
    /// `value.Value` can't carry `AcceptedTypes` without a circular import
    /// (`types.gleam` imports `value.gleam`).
    external_indicator_types: dict.Dict(String, AcceptedTypes),
    /// Optional declared SLO type from `"name" success_rate:` / `"name" time_slice:`
    /// header. When None, downstream consumers fall back to inferring the type
    /// from the formula shape at codegen.
    expectation_type: Option(ExpectationType),
  )
}

/// Validates measurements against SLO params and merges them.
/// Upgrades the phantom type from `Raw` to `MeasurementValidated` on success.
@internal
pub fn validate_measurements(
  measurements: List(Measurement(Raw)),
  slo_params: dict.Dict(String, ParamInfo),
) -> Result(List(Measurement(MeasurementValidated)), CompilationError) {
  // Validate all names are unique.
  use _ <- result.try(validations.validate_relevant_uniqueness(
    measurements,
    by: fn(b) { b.name },
    label: "measurement names",
  ))

  // Get SLO param types for validation.
  let slo_param_types = params_to_types(slo_params)

  // Validate exactly the right number of inputs and each input is the
  // correct type as per the param. A measurement needs to specify inputs for
  // all required_params from the SLO params.
  let measurement_slo_params_collection =
    measurements
    |> list.map(fn(measurement) { #(measurement, slo_param_types) })

  use _ <- result.try(validations.validate_inputs_for_collection(
    input_param_collections: measurement_slo_params_collection,
    get_inputs: fn(measurement) { measurement.inputs },
    get_params: fn(params) { params },
    with: fn(measurement) { "measurement '" <> measurement.name <> "'" },
    missing_inputs_ok: True,
  ))

  // Ensure no param name overshadowing by the measurement against SLO params.
  use _ <- result.try(
    validations.validate_no_overshadowing(
      measurement_slo_params_collection,
      get_check_collection: fn(measurement) { measurement.params },
      get_against_collection: fn(params) { params },
      get_error_label: fn(measurement) {
        "measurement '"
        <> measurement.name
        <> "' - overshadowing inherited SLO params: "
      },
    ),
  )

  // Reject external indicators whose source kind isn't supported. Aggregates
  // errors across measurements so authors see every bad source in one pass.
  use _ <- result.try(
    measurements
    |> list.map(fn(m) {
      validations.validate_external_indicator_sources(m.name, m.inputs)
    })
    |> errors.from_results(),
  )

  // At this point everything is validated, so we can merge SLO params with measurement params.
  let merged_param_measurements =
    measurements
    |> list.map(fn(measurement) {
      let all_params =
        slo_param_types
        |> dict.merge(measurement.params)

      Measurement(..measurement, params: all_params)
    })

  Ok(merged_param_measurements)
}
