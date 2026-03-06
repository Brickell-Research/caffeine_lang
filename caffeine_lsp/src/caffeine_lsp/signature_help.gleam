/// Signature help for expectation Provides blocks.
/// Shows the blueprint's required parameters and their types when the
/// cursor is inside an expectation's Provides section.
import caffeine_lang/linker/blueprints.{type Blueprint, type BlueprintValidated}
import caffeine_lang/types
import caffeine_lsp/completion
import caffeine_lsp/linker_diagnostics
import gleam/dict
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// Signature help information for a blueprint's parameters.
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
/// Provides block, showing the blueprint's required parameters.
pub fn get_signature_help(
  content: String,
  line: Int,
  character: Int,
  validated_blueprints: List(Blueprint(BlueprintValidated)),
) -> Option(SignatureHelp) {
  let lines = string.split(content, "\n")

  // Must be inside an expectation item.
  use _item_name <- option_then(completion.find_enclosing_item(lines, line))
  // Must be inside an Expectations block.
  use blueprint_ref <- option_then(completion.find_enclosing_blueprint_ref(
    lines,
    line,
  ))
  // Must find the matching validated blueprint.
  use blueprint <- result_to_option(
    list.find(validated_blueprints, fn(b) { b.name == blueprint_ref }),
  )

  let remaining_params = linker_diagnostics.compute_remaining_params(blueprint)
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
        blueprint_ref <> "(" <> string.join(param_labels, ", ") <> ")"

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

/// Helper to chain Option values using use syntax.
fn option_then(opt: Option(a), f: fn(a) -> Option(b)) -> Option(b) {
  case opt {
    option.Some(val) -> f(val)
    option.None -> option.None
  }
}

/// Convert a Result to an Option, discarding the error.
fn result_to_option(res: Result(a, b), f: fn(a) -> Option(c)) -> Option(c) {
  case res {
    Ok(val) -> f(val)
    Error(_) -> option.None
  }
}
