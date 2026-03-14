/// Signature help for expectation Provides blocks.
/// Shows the measurement's required parameters and their types when the
/// cursor is inside an expectation's Provides section.
import caffeine_lang/linker/measurements.{
  type Measurement, type MeasurementValidated,
}
import caffeine_lang/types
import caffeine_lsp/completion
import caffeine_lsp/measurement_utils
import gleam/dict
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// Signature help information for a measurement's parameters.
pub type SignatureHelp {
  SignatureHelp(
    label: String,
    parameters: List(ParameterInfo),
    active_parameter: Int,
  )
}

/// Information about a single parameter in the signature.
pub type ParameterInfo {
  ParameterInfo(label: String, documentation: String)
}

/// Returns signature help when the cursor is inside an expectation's
/// Provides block, showing the measurement's required parameters.
pub fn get_signature_help(
  content: String,
  line: Int,
  character: Int,
  validated_measurements: List(Measurement(MeasurementValidated)),
) -> Option(SignatureHelp) {
  let lines = string.split(content, "\n")

  // Must be inside an expectation item.
  use _item_name <- option.then(completion.find_enclosing_item(lines, line))
  // Must be inside an Expectations block.
  use measurement_ref <- option.then(completion.find_enclosing_measurement_ref(
    lines,
    line,
  ))
  // Must find the matching validated measurement.
  let measurement_index =
    measurement_utils.index_measurements(validated_measurements)
  use measurement <- option.then(
    dict.get(measurement_index, measurement_ref)
    |> option.from_result,
  )

  let remaining_params = measurement_utils.compute_remaining_params(measurement)
  let param_list =
    remaining_params
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })

  case param_list {
    [] -> option.None
    _ -> {
      let param_labels =
        list.map(param_list, fn(p) {
          p.0 <> ": " <> types.accepted_type_to_string(p.1)
        })
      let label =
        measurement_ref <> "(" <> string.join(param_labels, ", ") <> ")"

      let param_names = list.map(param_list, fn(p) { p.0 })
      let parameters =
        list.map(param_list, fn(p) {
          let type_str = types.accepted_type_to_string(p.1)
          let doc = case types.is_optional_or_defaulted(p.1) {
            True -> "Optional"
            False -> "Required"
          }
          ParameterInfo(label: p.0 <> ": " <> type_str, documentation: doc)
        })

      // Find active parameter by matching the field name on the cursor line.
      let active = find_active_parameter(lines, line, character, param_names)

      option.Some(SignatureHelp(
        label: label,
        parameters: parameters,
        active_parameter: active,
      ))
    }
  }
}

/// Find the active parameter index by extracting the field name
/// from the current line and matching it against parameter names.
fn find_active_parameter(
  lines: List(String),
  line: Int,
  _character: Int,
  param_names: List(String),
) -> Int {
  case list.drop(lines, line) {
    [line_text, ..] -> {
      let trimmed = string.trim(line_text)
      // Extract field name before ":"
      case string.split_once(trimmed, ":") {
        Ok(#(field_name, _)) -> {
          let name = string.trim(field_name)
          find_index(param_names, name, 0)
        }
        Error(_) -> -1
      }
    }
    [] -> -1
  }
}

/// Find the index of a value in a list, or return -1 if not found.
fn find_index(items: List(String), target: String, idx: Int) -> Int {
  case items {
    [] -> -1
    [first, ..rest] ->
      case first == target {
        True -> idx
        False -> find_index(rest, target, idx + 1)
      }
  }
}
