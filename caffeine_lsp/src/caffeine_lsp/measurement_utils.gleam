/// Shared utilities for working with validated measurements.
/// Used by completion, hover, signature help, and inlay hints.
import caffeine_lang/linker/measurements.{
  type Measurement, type MeasurementValidated,
}
import caffeine_lang/types.{type AcceptedTypes}
import gleam/dict
import gleam/list
import gleam/set

/// Compute params the expectation must provide — measurement params minus
/// keys already filled by the measurement's own inputs.
@internal
pub fn compute_remaining_params(
  measurement: Measurement(MeasurementValidated),
) -> dict.Dict(String, AcceptedTypes) {
  let measurement_input_keys = measurement.inputs |> dict.keys |> set.from_list
  measurement.params
  |> dict.filter(fn(key, _) { !set.contains(measurement_input_keys, key) })
}

/// Build a Dict index from a list of validated measurements for O(1) name lookups.
@internal
pub fn index_measurements(
  measurements: List(Measurement(MeasurementValidated)),
) -> dict.Dict(String, Measurement(MeasurementValidated)) {
  measurements
  |> list.map(fn(b) { #(b.name, b) })
  |> dict.from_list
}
