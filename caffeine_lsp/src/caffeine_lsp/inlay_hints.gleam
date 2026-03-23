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
/// Threads a `search_from` line cursor through all blocks and items so each
/// lookup scans forward from the previous result rather than restarting at 0.
fn get_expects_hints(
  lines: List(String),
  file: ast.ExpectsFile(ast.Parsed),
  start_line: Int,
  end_line: Int,
  measurement_index: Dict(String, Measurement(MeasurementValidated)),
) -> List(InlayHint) {
  let #(_, hints_rev) =
    list.fold(file.blocks, #(0, []), fn(acc, block) {
      case block.measurement {
        option.None -> acc
        option.Some(measurement_name) ->
          case dict.get(measurement_index, measurement_name) {
            Error(_) -> acc
            Ok(measurement) -> {
              let remaining_params =
                measurement_utils.compute_remaining_params(measurement)
              list.fold(block.items, acc, fn(acc2, item) {
                get_item_hints_acc(
                  lines,
                  item,
                  remaining_params,
                  start_line,
                  end_line,
                  acc2,
                )
              })
            }
          }
      }
    })
  list.reverse(hints_rev)
}

/// Accumulate type hints for fields in a single expectation item, threading
/// `search_from` forward so subsequent items skip already-scanned lines.
fn get_item_hints_acc(
  lines: List(String),
  item: ast.ExpectItem,
  remaining_params: Dict(String, AcceptedTypes),
  start_line: Int,
  end_line: Int,
  acc: #(Int, List(InlayHint)),
) -> #(Int, List(InlayHint)) {
  let #(search_from, hints) = acc
  let item_start =
    position_utils.find_item_start_line_from(
      lines,
      item.name,
      search_from,
      search_from,
    )
  list.fold(item.provides.fields, #(item_start, hints), fn(acc2, field) {
    let #(from, hints2) = acc2
    case dict.get(remaining_params, field.name) {
      Error(_) -> acc2
      Ok(expected_type) -> {
        let type_str = types.accepted_type_to_string(expected_type)
        let default_suffix = case expected_type {
          ModifierType(Defaulted(_, default_val)) -> " = " <> default_val
          _ -> ""
        }
        case find_field_line_from(lines, field.name, from) {
          Error(_) -> acc2
          Ok(#(field_line, field_col)) -> {
            let new_from = field_line + 1
            case field_line >= start_line && field_line <= end_line {
              False -> #(new_from, hints2)
              True ->
                #(new_from, [
                  InlayHint(
                    line: field_line,
                    column: field_col + string.length(field.name),
                    label: ": " <> type_str <> default_suffix,
                    kind: 1,
                    padding_left: True,
                  ),
                  ..hints2
                ])
            }
          }
        }
      }
    }
  })
}

/// Find the line and column of a field starting from `from_line`,
/// scanning forward without revisiting already-processed lines.
fn find_field_line_from(
  lines: List(String),
  field_name: String,
  from_line: Int,
) -> Result(#(Int, Int), Nil) {
  find_field_line_loop(list.drop(lines, from_line), field_name, from_line)
}

fn find_field_line_loop(
  lines: List(String),
  field_name: String,
  current_line: Int,
) -> Result(#(Int, Int), Nil) {
  case lines {
    [] -> Error(Nil)
    [line_text, ..rest] -> {
      let trimmed = string.trim(line_text)
      case string.starts_with(trimmed, field_name <> ":") {
        True -> {
          let col = string.length(line_text) - string.length(trimmed)
          Ok(#(current_line, col))
        }
        False -> find_field_line_loop(rest, field_name, current_line + 1)
      }
    }
  }
}
