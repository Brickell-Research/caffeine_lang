/// Inlay hints for expectation fields.
/// Shows type annotations next to field names in expectation Provides blocks,
/// based on the measurement's required parameter types.
import caffeine_lang/frontend/ast
import caffeine_lang/linker/measurements.{
  type Measurement, type MeasurementValidated,
}
import caffeine_lang/types.{type AcceptedTypes, Defaulted, ModifierType}
import caffeine_lsp/file_utils
import caffeine_lsp/measurement_utils
import caffeine_lsp/position_utils
import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import gleam/string

/// A single inlay hint to display in the editor.
pub type InlayHint {
  InlayHint(
    line: Int,
    column: Int,
    label: String,
    kind: Int,
    padding_left: Bool,
  )
}

/// Returns inlay hints for expectation fields within the given line range.
/// Shows the expected type next to each field name in Provides blocks.
pub fn get_inlay_hints(
  content: String,
  start_line: Int,
  end_line: Int,
  validated_measurements: List(Measurement(MeasurementValidated)),
) -> List(InlayHint) {
  case file_utils.parse(content) {
    Ok(file_utils.Expects(file)) -> {
      let lines = string.split(content, "\n")
      let measurement_index =
        measurement_utils.index_measurements(validated_measurements)
      get_expects_hints(lines, file, start_line, end_line, measurement_index)
    }
    _ -> []
  }
}

/// Generate hints for all expectation blocks in an expects file.
fn get_expects_hints(
  lines: List(String),
  file: ast.ExpectsFile(ast.Parsed),
  start_line: Int,
  end_line: Int,
  measurement_index: Dict(String, Measurement(MeasurementValidated)),
) -> List(InlayHint) {
  list.flat_map(file.blocks, fn(block) {
    case block.measurement {
      option.None -> []
      option.Some(measurement_name) ->
        case dict.get(measurement_index, measurement_name) {
          Error(_) -> []
          Ok(measurement) -> {
            let remaining_params =
              measurement_utils.compute_remaining_params(measurement)
            list.flat_map(block.items, fn(item) {
              get_item_hints(
                lines,
                item,
                remaining_params,
                start_line,
                end_line,
              )
            })
          }
        }
    }
  })
}

/// Generate type hints for fields in a single expectation item.
fn get_item_hints(
  lines: List(String),
  item: ast.ExpectItem,
  remaining_params: dict.Dict(String, AcceptedTypes),
  start_line: Int,
  end_line: Int,
) -> List(InlayHint) {
  // Find the item header line to scope field search within this item.
  let item_start = position_utils.find_item_start_line(lines, item.name, 0)
  list.filter_map(item.provides.fields, fn(field) {
    case dict.get(remaining_params, field.name) {
      Error(_) -> Error(Nil)
      Ok(expected_type) -> {
        let type_str = types.accepted_type_to_string(expected_type)
        let default_suffix = case expected_type {
          ModifierType(Defaulted(_, default_val)) -> " = " <> default_val
          _ -> ""
        }
        // Search for the field only after the item header line.
        case find_field_line(lines, field.name, 0, item_start) {
          Error(_) -> Error(Nil)
          Ok(#(field_line, field_col)) -> {
            case field_line >= start_line && field_line <= end_line {
              False -> Error(Nil)
              True ->
                Ok(InlayHint(
                  line: field_line,
                  column: field_col + string.length(field.name),
                  label: ": " <> type_str <> default_suffix,
                  kind: 1,
                  padding_left: True,
                ))
            }
          }
        }
      }
    }
  })
}

/// Find the line number and column of a field name in the source lines,
/// starting search from after `skip_until` to scope within the correct item.
fn find_field_line(
  lines: List(String),
  field_name: String,
  current_line: Int,
  skip_until: Int,
) -> Result(#(Int, Int), Nil) {
  case lines {
    [] -> Error(Nil)
    [line_text, ..rest] -> {
      case current_line > skip_until {
        False -> find_field_line(rest, field_name, current_line + 1, skip_until)
        True -> {
          let trimmed = string.trim(line_text)
          case string.starts_with(trimmed, field_name <> ":") {
            True -> {
              let col = string.length(line_text) - string.length(trimmed)
              Ok(#(current_line, col))
            }
            False ->
              find_field_line(rest, field_name, current_line + 1, skip_until)
          }
        }
      }
    }
  }
}
