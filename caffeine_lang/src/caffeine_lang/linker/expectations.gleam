import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/helpers
import caffeine_lang/linker/artifacts.{type ParamInfo}
import caffeine_lang/linker/measurements.{
  type Measurement, type MeasurementValidated,
}
import caffeine_lang/linker/validations
import caffeine_lang/string_distance
import caffeine_lang/value.{type Value}
import gleam/dict
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/set
import gleam/string

/// An Expectation is a concrete implementation of an Artifact + Measurement.
/// Unmeasured expectations have `measurement_ref: option.None` and skip codegen
/// but participate in dependency validation and graph generation.
pub type Expectation {
  Expectation(
    name: String,
    measurement_ref: Option(String),
    inputs: dict.Dict(String, Value),
  )
}

/// Validates expectations against measurements and returns paired with their optional measurements.
/// Measured expectations (measurement_ref = Some) are paired with their measurement.
/// Unmeasured expectations (measurement_ref = None) are validated against restricted params
/// (threshold, window_in_days, depends_on) and paired with None.
@internal
pub fn validate_expectations(
  expectations: List(Expectation),
  measurements: List(Measurement(MeasurementValidated)),
  slo_params slo_params: dict.Dict(String, ParamInfo),
  from source_path: String,
) -> Result(
  List(#(Expectation, Option(Measurement(MeasurementValidated)))),
  CompilationError,
) {
  // Partition into measured and unmeasured expectations.
  let #(measured, unmeasured) =
    list.partition(expectations, fn(e) { option.is_some(e.measurement_ref) })

  // Validate unique names across ALL expectations (measured + unmeasured).
  use _ <- result.try(validations.validate_relevant_uniqueness(
    expectations,
    by: fn(e) { e.name },
    label: "expectation names",
  ))

  // Validate measured expectations through existing path.
  use measured_pairs <- result.try(validate_measured_expectations(
    measured,
    measurements,
    source_path,
  ))

  // Validate unmeasured expectations against restricted params.
  use unmeasured_pairs <- result.try(validate_unmeasured_expectations(
    unmeasured,
    slo_params,
    source_path,
  ))

  Ok(list.append(measured_pairs, unmeasured_pairs))
}

/// Validates measured expectations against their measurements.
fn validate_measured_expectations(
  expectations: List(Expectation),
  measurements: List(Measurement(MeasurementValidated)),
  source_path: String,
) -> Result(
  List(#(Expectation, Option(Measurement(MeasurementValidated)))),
  CompilationError,
) {
  // Validate that all measurement_refs exist before mapping.
  use _ <- result.try(validate_measurement_refs(expectations, measurements))

  // Map expectations to measurements since we've validated all measurement_refs.
  let expectations_measurement_collection =
    helpers.map_reference_to_referrer_over_collection(
      references: measurements,
      referrers: expectations,
      reference_name: fn(b) { b.name },
      referrer_reference: fn(e) {
        let assert option.Some(ref) = e.measurement_ref
        ref
      },
    )

  let #(org, team, service) = helpers.extract_path_prefix(source_path)
  let path_prefix = org <> "." <> team <> "." <> service <> "."

  // Validate that expectation inputs don't overshadow measurement inputs.
  use _ <- result.try(check_input_overshadowing(
    expectations_measurement_collection,
    path_prefix,
  ))

  // Validate that expectation.inputs provides params NOT already provided by measurement.inputs.
  use _ <- result.try(validations.validate_inputs_for_collection(
    input_param_collections: expectations_measurement_collection,
    get_inputs: fn(expectation) { expectation.inputs },
    get_params: fn(measurement) {
      let measurement_input_keys = measurement.inputs |> dict.keys
      measurement.params
      |> dict.filter(fn(key, _) { !list.contains(measurement_input_keys, key) })
    },
    with: fn(expectation) {
      "expectation '" <> path_prefix <> expectation.name <> "'"
    },
    missing_inputs_ok: False,
  ))

  // Wrap measurements in Some for the return type.
  Ok(
    expectations_measurement_collection
    |> list.map(fn(pair) { #(pair.0, option.Some(pair.1)) }),
  )
}

/// Validates unmeasured expectations against restricted SLO params.
/// Unmeasured expectations may only provide: threshold, window_in_days, depends_on.
fn validate_unmeasured_expectations(
  expectations: List(Expectation),
  slo_params: dict.Dict(String, ParamInfo),
  source_path: String,
) -> Result(
  List(#(Expectation, Option(Measurement(MeasurementValidated)))),
  CompilationError,
) {
  let #(org, team, service) = helpers.extract_path_prefix(source_path)
  let path_prefix = org <> "." <> team <> "." <> service <> "."

  // Filter slo_params to only the allowed unmeasured params.
  let allowed_keys = set.from_list(["threshold", "window_in_days", "depends_on"])
  let restricted_params =
    slo_params
    |> dict.filter(fn(key, _) { set.contains(allowed_keys, key) })
    |> artifacts.params_to_types()

  // Validate inputs against restricted params.
  let input_param_collections =
    expectations
    |> list.map(fn(e) { #(e, restricted_params) })

  use _ <- result.try(validations.validate_inputs_for_collection(
    input_param_collections:,
    get_inputs: fn(expectation) { expectation.inputs },
    get_params: fn(params) { params },
    with: fn(expectation) {
      "expectation '" <> path_prefix <> expectation.name <> "'"
    },
    missing_inputs_ok: True,
  ))

  Ok(expectations |> list.map(fn(e) { #(e, option.None) }))
}

/// Validates that every measured expectation's measurement_ref matches an existing measurement.
/// Only called with measured expectations (those with Some(ref)).
/// Includes Levenshtein-based "did you mean?" suggestions for unknown refs.
fn validate_measurement_refs(
  expectations: List(Expectation),
  measurements: List(Measurement(MeasurementValidated)),
) -> Result(Nil, CompilationError) {
  let measurement_names = list.map(measurements, fn(b) { b.name })
  let measurement_name_set = set.from_list(measurement_names)
  let missing =
    expectations
    |> list.filter_map(fn(e) {
      case e.measurement_ref {
        option.Some(ref) ->
          case set.contains(measurement_name_set, ref) {
            True -> Error(Nil)
            False -> Ok(ref)
          }
        option.None -> Error(Nil)
      }
    })

  case missing {
    [] -> Ok(Nil)
    [single_ref] -> {
      let suggestion =
        string_distance.closest_match(single_ref, measurement_names)
      Error(errors.LinkerParseError(
        msg: "Unknown measurement reference: " <> single_ref,
        context: errors.ErrorContext(..errors.empty_context(), suggestion:),
      ))
    }
    _ ->
      Error(errors.linker_parse_error(
        msg: "Unknown measurement reference(s): " <> string.join(missing, ", "),
      ))
  }
}

fn check_input_overshadowing(
  expectations_measurement_collection: List(
    #(Expectation, Measurement(MeasurementValidated)),
  ),
  path_prefix: String,
) -> Result(Nil, CompilationError) {
  validations.validate_no_overshadowing(
    expectations_measurement_collection,
    get_check_collection: fn(expectation) { expectation.inputs },
    get_against_collection: fn(measurement) { measurement.inputs },
    get_error_label: fn(expectation) {
      "expectation '"
      <> path_prefix
      <> expectation.name
      <> "' - overshadowing inputs from measurement: "
    },
  )
}
