/// Linker-level diagnostics for expects files.
/// Validates expectation inputs against blueprint requirements,
/// surfacing missing fields, unknown fields, and type mismatches.
import caffeine_lang/frontend/pipeline
import caffeine_lang/linker/blueprints.{type Blueprint, type BlueprintValidated}
import caffeine_lang/linker/expectations.{type Expectation}
import caffeine_lang/source_file
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
import caffeine_lang/types.{type AcceptedTypes}
import caffeine_lsp/diagnostics.{
  type Diagnostic, Diagnostic, MissingRequiredFields, TypeMismatch, UnknownField,
}
import caffeine_lsp/lsp_types
import caffeine_lsp/position_utils
import gleam/dict
import gleam/list
import gleam/result
import gleam/set
import gleam/string

/// Compiles and validates blueprints from source content.
/// Returns validated blueprints for use in linker diagnostics,
/// or Error(Nil) if any compilation step fails.
pub fn compile_validated_blueprints(
  content: String,
) -> Result(List(Blueprint(BlueprintValidated)), Nil) {
  let source = source_file.SourceFile(path: "", content: content)
  use raw <- result.try(
    pipeline.compile_blueprints(source) |> result.replace_error(Nil),
  )
  blueprints.validate_blueprints(raw, stdlib_artifacts.standard_library())
  |> result.replace_error(Nil)
}

/// Returns linker-level diagnostics for an expects file.
/// Validates each expectation's inputs against its referenced blueprint.
pub fn get_linker_diagnostics(
  content: String,
  all_validated_blueprints: List(Blueprint(BlueprintValidated)),
) -> List(Diagnostic) {
  let source = source_file.SourceFile(path: "lsp", content: content)
  case pipeline.compile_expects(source) {
    Error(_) -> []
    Ok(expectations) ->
      expectations
      |> list.flat_map(check_expectation(content, _, all_validated_blueprints))
  }
}

/// Check a single expectation against all known blueprints.
fn check_expectation(
  content: String,
  expectation: Expectation,
  blueprints: List(Blueprint(BlueprintValidated)),
) -> List(Diagnostic) {
  case list.find(blueprints, fn(b) { b.name == expectation.blueprint_ref }) {
    Error(Nil) -> []
    Ok(blueprint) -> {
      let remaining_params = compute_remaining_params(blueprint)
      list.flatten([
        check_missing_required(content, expectation, remaining_params),
        check_unknown_fields(content, expectation, remaining_params),
        check_type_mismatches(content, expectation, remaining_params),
      ])
    }
  }
}

/// Compute params the expectation must provide — blueprint params minus
/// keys already filled by the blueprint's own inputs.
fn compute_remaining_params(
  blueprint: Blueprint(BlueprintValidated),
) -> dict.Dict(String, AcceptedTypes) {
  let blueprint_input_keys = blueprint.inputs |> dict.keys |> set.from_list
  blueprint.params
  |> dict.filter(fn(key, _) { !set.contains(blueprint_input_keys, key) })
}

/// Check for required fields missing from the expectation.
fn check_missing_required(
  content: String,
  expectation: Expectation,
  remaining_params: dict.Dict(String, AcceptedTypes),
) -> List(Diagnostic) {
  let input_keys = expectation.inputs |> dict.keys |> set.from_list
  let missing =
    remaining_params
    |> dict.filter(fn(key, typ) {
      !set.contains(input_keys, key) && !types.is_optional_or_defaulted(typ)
    })
    |> dict.keys
    |> list.sort(string.compare)

  case missing {
    [] -> []
    _ -> {
      let #(line, col) =
        position_utils.find_name_position(content, expectation.name)
      let message = "Missing required fields: " <> string.join(missing, ", ")
      [
        Diagnostic(
          line: line,
          column: col,
          end_column: col + string.length(expectation.name),
          severity: lsp_types.diagnostic_severity_to_int(lsp_types.DsError),
          message: message,
          code: MissingRequiredFields,
        ),
      ]
    }
  }
}

/// Check for fields in the expectation that don't exist in the blueprint.
fn check_unknown_fields(
  content: String,
  expectation: Expectation,
  remaining_params: dict.Dict(String, AcceptedTypes),
) -> List(Diagnostic) {
  let param_keys = remaining_params |> dict.keys |> set.from_list
  let unknown_keys =
    expectation.inputs
    |> dict.keys
    |> list.filter(fn(key) { !set.contains(param_keys, key) })

  unknown_keys
  |> list.map(fn(key) {
    let #(line, col) = position_utils.find_name_position(content, key)
    Diagnostic(
      line: line,
      column: col,
      end_column: col + string.length(key),
      severity: lsp_types.diagnostic_severity_to_int(lsp_types.DsError),
      message: "Unknown field '" <> key <> "' — not in blueprint requires",
      code: UnknownField,
    )
  })
}

/// Check type mismatches between expectation values and blueprint param types.
fn check_type_mismatches(
  content: String,
  expectation: Expectation,
  remaining_params: dict.Dict(String, AcceptedTypes),
) -> List(Diagnostic) {
  expectation.inputs
  |> dict.to_list
  |> list.filter_map(fn(pair) {
    let #(key, val) = pair
    case dict.get(remaining_params, key) {
      Error(Nil) -> Error(Nil)
      Ok(expected_type) ->
        case types.validate_value(expected_type, val) {
          Ok(_) -> Error(Nil)
          Error(_) -> {
            let #(line, col) = position_utils.find_name_position(content, key)
            let message =
              "Expected "
              <> types.accepted_type_to_string(expected_type)
              <> " for '"
              <> key
              <> "'"
            Ok(Diagnostic(
              line: line,
              column: col,
              end_column: col + string.length(key),
              severity: lsp_types.diagnostic_severity_to_int(lsp_types.DsError),
              message: message,
              code: TypeMismatch,
            ))
          }
        }
    }
  })
}
