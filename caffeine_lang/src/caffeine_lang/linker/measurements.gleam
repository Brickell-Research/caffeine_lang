import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/linker/artifacts.{type ParamInfo}
import caffeine_lang/linker/validations
import caffeine_lang/types.{type AcceptedTypes}
import caffeine_lang/value.{type Value}
import gleam/dict
import gleam/list
import gleam/result

/// Marker type for measurements that have not yet been validated.
pub type Raw

/// Marker type for measurements that have passed validation.
pub type MeasurementValidated

/// A Measurement that references one or more Artifacts with parameters and inputs. It provides further params
/// for the Expectation to satisfy while providing a partial set of inputs for the Artifact's params.
/// The phantom type parameter `state` tracks whether the measurement is `Raw` or `MeasurementValidated`.
pub type Measurement(state) {
  Measurement(
    name: String,
    params: dict.Dict(String, AcceptedTypes),
    inputs: dict.Dict(String, Value),
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
  let slo_param_types = artifacts.params_to_types(slo_params)

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
        <> "' - overshadowing inherited_params from artifact: "
      },
    ),
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
