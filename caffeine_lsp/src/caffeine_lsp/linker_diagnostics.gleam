/// Linker-level diagnostics for expects files.
/// Validates expectation inputs against measurement requirements,
/// surfacing missing fields, unknown fields, and type mismatches.
import caffeine_lang/frontend/pipeline
import caffeine_lang/linker/expectations.{type Expectation}
import caffeine_lang/linker/measurements.{
  type Measurement, type MeasurementValidated,
}
import caffeine_lang/source_file
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
import caffeine_lang/types.{type AcceptedTypes}
import caffeine_lang/value
import caffeine_lsp/diagnostics.{
  type Diagnostic, Diagnostic, MissingRequiredFields, TypeMismatch, UnknownField,
}
import caffeine_lsp/lsp_types
import caffeine_lsp/measurement_utils
import caffeine_lsp/position_utils
import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import gleam/set
import gleam/string

/// Compiles and validates measurements from source content.
/// Returns validated measurements for use in linker diagnostics,
/// or Error(Nil) if any compilation step fails.
pub fn compile_validated_measurements(
  content: String,
) -> Result(List(Measurement(MeasurementValidated)), Nil) {
  let source = source_file.SourceFile(path: "", content: content)
  use raw <- result.try(
    pipeline.compile_measurements(source) |> result.replace_error(Nil),
  )
  measurements.validate_measurements(raw, stdlib_artifacts.slo_params())
  |> result.replace_error(Nil)
}

/// Returns linker-level diagnostics for an expects file.
/// Validates each expectation's inputs against its referenced measurement.
/// Lines are split once and threaded through the fold to avoid O(n²) re-splitting.
pub fn get_linker_diagnostics(
  content: String,
  all_validated_measurements: List(Measurement(MeasurementValidated)),
) -> List(Diagnostic) {
  let source = source_file.SourceFile(path: "lsp", content: content)
  case pipeline.compile_expects(source) {
    Error(_) -> []
    Ok(expectations) -> {
      let measurement_index =
        measurement_utils.index_measurements(all_validated_measurements)
      let lines = string.split(content, "\n")
      let #(diagnostics_rev, _) =
        list.fold(expectations, #([], 0), fn(acc, expectation) {
          let #(diags_rev, search_from) = acc
          let anchor_line =
            position_utils.find_name_in_lines_from(
              lines,
              expectation.name,
              search_from,
            )
            |> result.map(fn(pos) { pos.0 })
            |> result.unwrap(search_from)
          let new_diags =
            check_expectation(lines, expectation, measurement_index, anchor_line)
          let updated_rev =
            list.fold(new_diags, diags_rev, fn(a, d) { [d, ..a] })
          #(updated_rev, anchor_line + 1)
        })
      list.reverse(diagnostics_rev)
    }
  }
}

/// Check a single expectation against an indexed Dict of measurements.
/// Unmeasured expectations (measurement_ref = None) produce no diagnostics.
fn check_expectation(
  lines: List(String),
  expectation: Expectation,
  measurement_index: dict.Dict(String, Measurement(MeasurementValidated)),
  anchor_line: Int,
) -> List(Diagnostic) {
  case expectation.measurement_ref {
    option.None -> []
    option.Some(ref) ->
      check_measured_expectation(
        lines,
        expectation,
        measurement_index,
        anchor_line,
        ref,
      )
  }
}

/// Check a measured expectation against an indexed Dict of measurements.
fn check_measured_expectation(
  lines: List(String),
  expectation: Expectation,
  measurement_index: dict.Dict(String, Measurement(MeasurementValidated)),
  anchor_line: Int,
  measurement_ref: String,
) -> List(Diagnostic) {
  case dict.get(measurement_index, measurement_ref) {
    Error(Nil) -> []
    Ok(measurement) -> {
      let remaining_params =
        measurement_utils.compute_remaining_params(measurement)
      list.flatten([
        check_missing_required(lines, expectation, remaining_params, anchor_line),
        check_unknown_fields(lines, expectation, remaining_params, anchor_line),
        check_type_mismatches(lines, expectation, remaining_params, anchor_line),
      ])
    }
  }
}

/// Check for required fields missing from the expectation.
fn check_missing_required(
  lines: List(String),
  expectation: Expectation,
  remaining_params: dict.Dict(String, AcceptedTypes),
  anchor_line: Int,
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
        position_utils.find_name_in_lines_from(
          lines,
          expectation.name,
          anchor_line,
        )
        |> result.unwrap(#(0, 0))
      let message = "Missing required fields: " <> string.join(missing, ", ")
      [
        Diagnostic(
          line: line,
          column: col,
          end_column: col + string.length(expectation.name),
          severity: lsp_types.DsError,
          message: message,
          code: MissingRequiredFields,
        ),
      ]
    }
  }
}

/// Check for fields in the expectation that don't exist in the measurement.
fn check_unknown_fields(
  lines: List(String),
  expectation: Expectation,
  remaining_params: dict.Dict(String, AcceptedTypes),
  anchor_line: Int,
) -> List(Diagnostic) {
  let param_keys = remaining_params |> dict.keys |> set.from_list
  let unknown_keys =
    expectation.inputs
    |> dict.keys
    |> list.filter(fn(key) { !set.contains(param_keys, key) })

  unknown_keys
  |> list.map(fn(key) {
    let #(line, col) =
      position_utils.find_name_in_lines_from(lines, key, anchor_line)
      |> result.unwrap(#(0, 0))
    Diagnostic(
      line: line,
      column: col,
      end_column: col + string.length(key),
      severity: lsp_types.DsError,
      message: "Unknown field '" <> key <> "' — not in measurement requires",
      code: UnknownField,
    )
  })
}

/// Check type mismatches between expectation values and measurement param types.
fn check_type_mismatches(
  lines: List(String),
  expectation: Expectation,
  remaining_params: dict.Dict(String, AcceptedTypes),
  anchor_line: Int,
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
            let #(line, col) =
              position_utils.find_name_in_lines_from(lines, key, anchor_line)
              |> result.unwrap(#(0, 0))
            let message =
              "Expected "
              <> types.accepted_type_to_string(expected_type)
              <> " but got "
              <> value.classify(val)
              <> " for '"
              <> key
              <> "'"
            Ok(Diagnostic(
              line: line,
              column: col,
              end_column: col + string.length(key),
              severity: lsp_types.DsError,
              message: message,
              code: TypeMismatch,
            ))
          }
        }
    }
  })
}
