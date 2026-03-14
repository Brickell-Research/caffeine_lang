import caffeine_lang/frontend/ast.{
  type ExpectsBlock, type ExpectsFile, type MeasurementsFile, type Parsed,
  type Struct, type Value, ExtendableRequires, TypeValue,
}
import caffeine_lang/frontend/parser_error.{type ParserError}
import caffeine_lang/frontend/tokenizer_error.{type TokenizerError}
import caffeine_lang/frontend/validator.{type ValidatorError}
import caffeine_lang/types.{type ParsedType, ParsedTypeAliasRef}
import caffeine_lsp/file_utils
import caffeine_lsp/lsp_types.{DsError, DsWarning}
import caffeine_lsp/position_utils
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/order
import gleam/result
import gleam/set
import gleam/string

/// Structured diagnostic codes for machine-readable identification.
pub type DiagnosticCode {
  QuotedFieldName
  MeasurementNotFound
  DependencyNotFound
  MissingRequiredFields
  TypeMismatch
  UnknownField
  UnusedExtendable
  UnusedTypeAlias
  DeadMeasurement
  NoDiagnosticCode
}

/// Converts a DiagnosticCode to its wire-format string, if applicable.
pub fn diagnostic_code_to_string(code: DiagnosticCode) -> Option(String) {
  case code {
    QuotedFieldName -> option.Some("quoted-field-name")
    MeasurementNotFound -> option.Some("measurement-not-found")
    DependencyNotFound -> option.Some("dependency-not-found")
    MissingRequiredFields -> option.Some("missing-required-fields")
    TypeMismatch -> option.Some("type-mismatch")
    UnknownField -> option.Some("unknown-field")
    UnusedExtendable -> option.Some("unused-extendable")
    UnusedTypeAlias -> option.Some("unused-type-alias")
    DeadMeasurement -> option.Some("dead-measurement")
    NoDiagnosticCode -> option.None
  }
}

/// A diagnostic to send to the editor.
pub type Diagnostic {
  Diagnostic(
    line: Int,
    column: Int,
    end_column: Int,
    severity: lsp_types.DiagnosticSeverity,
    message: String,
    code: DiagnosticCode,
  )
}

/// Run all diagnostic checks with a single parse pass.
/// Combines validation, cross-file measurement, and dependency diagnostics.
pub fn get_all_diagnostics(
  content: String,
  known_measurements: List(String),
  known_identifiers: List(String),
) -> List(Diagnostic) {
  use <- bool.guard(when: string.trim(content) == "", return: [])
  let parsed = file_utils.parse(content)
  let validation_diags = get_diagnostics_from_parsed(content, parsed)
  case parsed {
    Ok(file) -> {
      let cross_file_diags =
        get_cross_file_from_parsed(content, file, known_measurements)
      let dep_diags =
        get_dependency_from_parsed(content, file, known_identifiers)
      list.flatten([validation_diags, cross_file_diags, dep_diags])
    }
    Error(_) -> validation_diags
  }
}

/// Analyze source text and return diagnostics.
/// Tries to parse as measurements first, then as expects.
/// If parsing succeeds, runs the validator for additional checks.
pub fn get_diagnostics(content: String) -> List(Diagnostic) {
  use <- bool.guard(when: string.trim(content) == "", return: [])
  get_diagnostics_from_parsed(content, file_utils.parse(content))
}

/// Validation diagnostics from a pre-parsed result.
fn get_diagnostics_from_parsed(
  content: String,
  parsed: Result(file_utils.ParsedFile, #(List(ParserError), List(ParserError))),
) -> List(Diagnostic) {
  case parsed {
    Ok(file_utils.Measurements(file)) ->
      case validator.validate_measurements_file(file) {
        Ok(_) -> get_unused_warnings_measurements(content, file)
        Error(errs) -> list.map(errs, validator_error_to_diagnostic(content, _))
      }
    Ok(file_utils.Expects(file)) ->
      case validator.validate_expects_file(file) {
        Ok(_) -> get_unused_warnings_expects(content, file)
        Error(errs) -> list.map(errs, validator_error_to_diagnostic(content, _))
      }
    Error(#(bp_errs, ex_errs)) ->
      pick_further_errors(bp_errs, ex_errs)
      |> list.map(parser_error_to_diagnostic)
  }
}

/// Check measurement references in an expects file against known workspace measurements.
/// Returns diagnostics for any measurement refs not found in the known list.
pub fn get_cross_file_diagnostics(
  content: String,
  known_measurements: List(String),
) -> List(Diagnostic) {
  use <- bool.guard(when: string.trim(content) == "", return: [])
  case file_utils.parse(content) {
    Ok(parsed) ->
      get_cross_file_from_parsed(content, parsed, known_measurements)
    _ -> []
  }
}

/// Measurement reference checks from a successfully parsed file.
fn get_cross_file_from_parsed(
  content: String,
  parsed: file_utils.ParsedFile,
  known_measurements: List(String),
) -> List(Diagnostic) {
  case parsed {
    file_utils.Expects(file) ->
      file.blocks
      |> list.filter_map(fn(block) {
        check_measurement_ref(content, block, known_measurements)
      })
    _ -> []
  }
}

/// Check a single expects block's measurement reference against known measurements.
/// Unmeasured blocks (measurement = None) are skipped.
fn check_measurement_ref(
  content: String,
  block: ExpectsBlock,
  known_measurements: List(String),
) -> Result(Diagnostic, Nil) {
  case block.measurement {
    option.None -> Error(Nil)
    option.Some(measurement) -> {
      use <- bool.guard(
        when: list.contains(known_measurements, measurement),
        return: Error(Nil),
      )
      let #(line, col) =
        position_utils.find_name_position(content, measurement)
        |> result.unwrap(#(0, 0))
      Ok(Diagnostic(
        line: line,
        column: col,
        end_column: col + string.length(measurement),
        severity: DsError,
        message: "Measurement '" <> measurement <> "' not found in workspace",
        code: MeasurementNotFound,
      ))
    }
  }
}

/// Check dependency relation targets against known expectation identifiers.
/// Returns diagnostics for any dependency targets not found in the known list.
pub fn get_cross_file_dependency_diagnostics(
  content: String,
  known_identifiers: List(String),
) -> List(Diagnostic) {
  use <- bool.guard(when: string.trim(content) == "", return: [])
  case file_utils.parse(content) {
    Ok(parsed) -> get_dependency_from_parsed(content, parsed, known_identifiers)
    Error(_) -> []
  }
}

/// Dependency checks from a successfully parsed file.
fn get_dependency_from_parsed(
  content: String,
  parsed: file_utils.ParsedFile,
  known_identifiers: List(String),
) -> List(Diagnostic) {
  let targets = extract_relation_targets(parsed)
  targets
  |> list.unique
  |> list.filter_map(fn(target) {
    check_dependency_ref(content, target, known_identifiers)
  })
}

/// Extract all dependency target strings from relation fields in a parsed file.
fn extract_relation_targets(parsed: file_utils.ParsedFile) -> List(String) {
  case parsed {
    file_utils.Measurements(file) ->
      extract_relation_targets_from_measurements(file)
    file_utils.Expects(file) -> extract_relation_targets_from_expects(file)
  }
}

fn extract_relation_targets_from_measurements(
  file: MeasurementsFile(Parsed),
) -> List(String) {
  file.items
  |> list.flat_map(fn(item) {
    extract_relation_targets_from_struct(item.provides)
  })
}

fn extract_relation_targets_from_expects(
  file: ExpectsFile(Parsed),
) -> List(String) {
  file.blocks
  |> list.flat_map(fn(block) {
    block.items
    |> list.flat_map(fn(item) {
      extract_relation_targets_from_struct(item.provides)
    })
  })
}

/// Walk a provides struct to find relation target strings.
fn extract_relation_targets_from_struct(provides: Struct) -> List(String) {
  provides.fields
  |> list.filter_map(fn(field) {
    case field.name {
      "relations" -> Ok(extract_strings_from_relations(field.value))
      _ -> Error(Nil)
    }
  })
  |> list.flatten
}

/// Extract string values from a relations literal struct (hard/soft lists).
fn extract_strings_from_relations(value: ast.Value) -> List(String) {
  case value {
    ast.LiteralValue(ast.LiteralStruct(fields, _)) ->
      fields
      |> list.flat_map(fn(f) {
        case f.value {
          ast.LiteralValue(ast.LiteralList(elements)) ->
            elements
            |> list.filter_map(fn(elem) {
              case elem {
                ast.LiteralString(s) -> Ok(s)
                _ -> Error(Nil)
              }
            })
          _ -> []
        }
      })
    _ -> []
  }
}

/// Check a single dependency target against known identifiers.
fn check_dependency_ref(
  content: String,
  target: String,
  known_identifiers: List(String),
) -> Result(Diagnostic, Nil) {
  use <- bool.guard(
    when: list.contains(known_identifiers, target),
    return: Error(Nil),
  )
  let #(line, col) =
    position_utils.find_name_position(content, target)
    |> result.unwrap(#(0, 0))
  Ok(Diagnostic(
    line: line,
    column: col,
    end_column: col + string.length(target),
    severity: DsError,
    message: "Dependency '" <> target <> "' not found in workspace",
    code: DependencyNotFound,
  ))
}

/// Build a diagnostic at the position of a name in the source.
fn name_diagnostic(
  content: String,
  name: String,
  severity: lsp_types.DiagnosticSeverity,
  message: String,
) -> Diagnostic {
  let #(line, col) =
    position_utils.find_name_position(content, name)
    |> result.unwrap(#(0, 0))
  Diagnostic(
    line: line,
    column: col,
    end_column: col + string.length(name),
    severity: severity,
    message: message,
    code: NoDiagnosticCode,
  )
}

/// Detect unused extendables and type aliases in a measurements file.
fn get_unused_warnings_measurements(
  content: String,
  file: MeasurementsFile(Parsed),
) -> List(Diagnostic) {
  let extendable_warnings =
    get_unused_extendable_warnings(
      content,
      file.extendables,
      list.flat_map(file.items, fn(i) { i.extends }),
    )
  let alias_warnings =
    get_unused_alias_warnings(
      content,
      file.type_aliases,
      collect_alias_refs_from_measurement(file),
    )
  list.append(extendable_warnings, alias_warnings)
}

/// Detect unused extendables in an expects file.
fn get_unused_warnings_expects(
  content: String,
  file: ExpectsFile(Parsed),
) -> List(Diagnostic) {
  get_unused_extendable_warnings(
    content,
    file.extendables,
    list.flat_map(file.blocks, fn(b) {
      list.flat_map(b.items, fn(i) { i.extends })
    }),
  )
}

/// Emit warnings for extendables that are defined but never referenced.
fn get_unused_extendable_warnings(
  content: String,
  extendables: List(ast.Extendable),
  all_extends_refs: List(String),
) -> List(Diagnostic) {
  let referenced = set.from_list(all_extends_refs)
  let defined = list.map(extendables, fn(e) { e.name })
  list.filter(defined, fn(name) { !set.contains(referenced, name) })
  |> list.map(fn(name) {
    let #(line, col) =
      position_utils.find_name_position(content, name)
      |> result.unwrap(#(0, 0))
    Diagnostic(
      line: line,
      column: col,
      end_column: col + string.length(name),
      severity: DsWarning,
      message: "Extendable '" <> name <> "' is defined but never used",
      code: UnusedExtendable,
    )
  })
}

/// Emit warnings for type aliases that are defined but never referenced.
fn get_unused_alias_warnings(
  content: String,
  aliases: List(ast.TypeAlias),
  all_alias_refs: set.Set(String),
) -> List(Diagnostic) {
  let defined = list.map(aliases, fn(ta) { ta.name })
  list.filter(defined, fn(name) { !set.contains(all_alias_refs, name) })
  |> list.map(fn(name) {
    let #(line, col) =
      position_utils.find_name_position(content, name)
      |> result.unwrap(#(0, 0))
    Diagnostic(
      line: line,
      column: col,
      end_column: col + string.length(name),
      severity: DsWarning,
      message: "Type alias '" <> name <> "' is defined but never used",
      code: UnusedTypeAlias,
    )
  })
}

/// Collect all type alias references from a measurements file's Requires fields
/// and from other type alias definitions (chained aliases).
fn collect_alias_refs_from_measurement(
  file: MeasurementsFile(Parsed),
) -> set.Set(String) {
  // Refs from Requires fields in measurement items
  let field_refs =
    list.flat_map(file.items, fn(i) {
      list.flat_map(i.requires.fields, fn(f) {
        collect_alias_refs_from_value(f.value)
      })
    })
  // Refs from Requires extendable fields
  let extendable_refs =
    list.flat_map(file.extendables, fn(e) {
      case e.kind {
        ExtendableRequires ->
          list.flat_map(e.body.fields, fn(f) {
            collect_alias_refs_from_value(f.value)
          })
        _ -> []
      }
    })
  // Refs from type alias definitions (aliases referencing other aliases)
  let alias_refs =
    list.flat_map(file.type_aliases, fn(ta) {
      collect_alias_refs_from_parsed_type(ta.type_)
    })
  set.from_list(list.flatten([field_refs, extendable_refs, alias_refs]))
}

/// Extract alias reference names from a field value.
fn collect_alias_refs_from_value(value: Value) -> List(String) {
  case value {
    TypeValue(parsed_type) -> collect_alias_refs_from_parsed_type(parsed_type)
    _ -> []
  }
}

/// Recursively collect alias reference names from a parsed type.
fn collect_alias_refs_from_parsed_type(parsed_type: ParsedType) -> List(String) {
  case parsed_type {
    ParsedTypeAliasRef(name) -> [name]
    types.ParsedPrimitive(_) -> []
    types.ParsedCollection(collection) ->
      case collection {
        types.List(inner) -> collect_alias_refs_from_parsed_type(inner)
        types.Dict(key, val) ->
          list.append(
            collect_alias_refs_from_parsed_type(key),
            collect_alias_refs_from_parsed_type(val),
          )
      }
    types.ParsedModifier(modifier) ->
      case modifier {
        types.Optional(inner) -> collect_alias_refs_from_parsed_type(inner)
        types.Defaulted(inner, _) -> collect_alias_refs_from_parsed_type(inner)
      }
    types.ParsedRefinement(refinement) ->
      case refinement {
        types.OneOf(inner, _) -> collect_alias_refs_from_parsed_type(inner)
        types.InclusiveRange(inner, _, _) ->
          collect_alias_refs_from_parsed_type(inner)
      }
    types.ParsedRecord(fields) ->
      dict.values(fields)
      |> list.flat_map(collect_alias_refs_from_parsed_type)
  }
}

/// Detect measurements with no expectations across the workspace.
pub fn get_dead_measurement_diagnostics(
  content: String,
  all_referenced_measurements: List(String),
) -> List(Diagnostic) {
  use <- bool.guard(when: string.trim(content) == "", return: [])
  case file_utils.parse(content) {
    Ok(file_utils.Measurements(file)) -> {
      let referenced = set.from_list(all_referenced_measurements)
      list.filter_map(file.items, fn(item) {
        case set.contains(referenced, item.name) {
          True -> Error(Nil)
          False ->
            Ok({
              let #(line, col) =
                position_utils.find_name_position(content, item.name)
                |> result.unwrap(#(0, 0))
              Diagnostic(
                line: line,
                column: col,
                end_column: col + string.length(item.name),
                severity: DsWarning,
                message: "Measurement '"
                  <> item.name
                  <> "' has no expectations in the workspace",
                code: DeadMeasurement,
              )
            })
        }
      })
    }
    _ -> []
  }
}

fn validator_error_to_diagnostic(
  content: String,
  err: ValidatorError,
) -> Diagnostic {
  case err {
    validator.DuplicateExtendable(name) ->
      name_diagnostic(
        content,
        name,
        DsError,
        "Duplicate extendable '" <> name <> "'",
      )
    validator.UndefinedExtendable(name, referenced_by, _candidates) ->
      name_diagnostic(
        content,
        name,
        DsError,
        "Undefined extendable '"
          <> name
          <> "' referenced by '"
          <> referenced_by
          <> "'",
      )
    validator.DuplicateExtendsReference(name, referenced_by) ->
      name_diagnostic(
        content,
        name,
        DsWarning,
        "Duplicate extends reference '"
          <> name
          <> "' in '"
          <> referenced_by
          <> "'",
      )
    validator.InvalidExtendableKind(name, expected, got) ->
      name_diagnostic(
        content,
        name,
        DsError,
        "Extendable '" <> name <> "' must be " <> expected <> ", got " <> got,
      )
    validator.UndefinedTypeAlias(name, referenced_by, _candidates) ->
      name_diagnostic(
        content,
        name,
        DsError,
        "Undefined type alias '"
          <> name
          <> "' referenced by '"
          <> referenced_by
          <> "'",
      )
    validator.DuplicateTypeAlias(name) ->
      name_diagnostic(
        content,
        name,
        DsError,
        "Duplicate type alias '" <> name <> "'",
      )
    validator.CircularTypeAlias(name, cycle) -> {
      let cycle_str = string.join(cycle, " -> ")
      name_diagnostic(
        content,
        name,
        DsError,
        "Circular type alias '" <> name <> "': " <> cycle_str,
      )
    }
    validator.InvalidDictKeyTypeAlias(alias_name, resolved_to, referenced_by) ->
      name_diagnostic(
        content,
        alias_name,
        DsError,
        "Dict key type '"
          <> alias_name
          <> "' resolves to '"
          <> resolved_to
          <> "' (must be String-based), in '"
          <> referenced_by
          <> "'",
      )
    validator.ExtendableOvershadowing(field_name, item_name, extendable_name) ->
      name_diagnostic(
        content,
        field_name,
        DsError,
        "Field '"
          <> field_name
          <> "' in '"
          <> item_name
          <> "' overshadows field from extendable '"
          <> extendable_name
          <> "'",
      )
    validator.ExtendableTypeAliasNameCollision(name) ->
      name_diagnostic(
        content,
        name,
        DsError,
        "Name '" <> name <> "' is used as both an extendable and a type alias",
      )
    validator.InvalidRefinementValue(value, expected_type, referenced_by) ->
      name_diagnostic(
        content,
        value,
        DsError,
        "Refinement value '"
          <> value
          <> "' is not a valid "
          <> expected_type
          <> " literal, in '"
          <> referenced_by
          <> "'",
      )
    validator.InvalidPercentageBounds(value, referenced_by) ->
      name_diagnostic(
        content,
        value,
        DsError,
        "Percentage value '"
          <> value
          <> "' must be between 0.0 and 100.0, in '"
          <> referenced_by
          <> "'",
      )
  }
}

fn parser_error_to_diagnostic(err: ParserError) -> Diagnostic {
  case err {
    parser_error.TokenizerError(tok_err) ->
      tokenizer_error_to_diagnostic(tok_err)
    parser_error.UnexpectedToken(expected, got, line, column) -> {
      let col = to_lsp_column(column)
      Diagnostic(
        line: to_lsp_line(line),
        column: col,
        end_column: col + string.length(got),
        severity: DsError,
        message: "Unexpected token: expected " <> expected <> ", got " <> got,
        code: NoDiagnosticCode,
      )
    }
    parser_error.UnexpectedEOF(expected, line, column) -> {
      let col = to_lsp_column(column)
      Diagnostic(
        line: to_lsp_line(line),
        column: col,
        end_column: col + 1,
        severity: DsError,
        message: "Unexpected end of file: expected " <> expected,
        code: NoDiagnosticCode,
      )
    }
    parser_error.UnknownType(name, line, column) -> {
      let col = to_lsp_column(column)
      Diagnostic(
        line: to_lsp_line(line),
        column: col,
        end_column: col + string.length(name),
        severity: DsError,
        message: "Unknown type '" <> name <> "'",
        code: NoDiagnosticCode,
      )
    }
    parser_error.InvalidRefinement(message, line, column) -> {
      let col = to_lsp_column(column)
      Diagnostic(
        line: to_lsp_line(line),
        column: col,
        end_column: col + 1,
        severity: DsError,
        message: "Invalid refinement: " <> message,
        code: NoDiagnosticCode,
      )
    }
    parser_error.QuotedFieldName(name, line, column) -> {
      let col = to_lsp_column(column)
      Diagnostic(
        line: to_lsp_line(line),
        column: col,
        end_column: col + string.length(name) + 2,
        severity: DsError,
        message: "Field names should not be quoted. Use '"
          <> name
          <> "' instead",
        code: QuotedFieldName,
      )
    }
    parser_error.InvalidTypeAliasName(name, message, line, column) -> {
      let col = to_lsp_column(column)
      Diagnostic(
        line: to_lsp_line(line),
        column: col,
        end_column: col + string.length(name),
        severity: DsError,
        message: "Invalid type alias name '" <> name <> "': " <> message,
        code: NoDiagnosticCode,
      )
    }
  }
}

fn tokenizer_error_to_diagnostic(err: TokenizerError) -> Diagnostic {
  case err {
    tokenizer_error.UnterminatedString(line, column) -> {
      let col = to_lsp_column(column)
      Diagnostic(
        line: to_lsp_line(line),
        column: col,
        end_column: col + 1,
        severity: DsError,
        message: "Unterminated string",
        code: NoDiagnosticCode,
      )
    }
    tokenizer_error.InvalidCharacter(line, column, char) -> {
      let col = to_lsp_column(column)
      Diagnostic(
        line: to_lsp_line(line),
        column: col,
        end_column: col + string.length(char),
        severity: DsError,
        message: "Invalid character '" <> char <> "'",
        code: NoDiagnosticCode,
      )
    }
  }
}

/// Pick the error list that got further in the source.
/// When both parsers fail, the one that progressed further is more likely
/// to match the file's actual format and its errors will be more relevant.
fn pick_further_errors(
  a: List(ParserError),
  b: List(ParserError),
) -> List(ParserError) {
  let a_max = max_error_line(a)
  let b_max = max_error_line(b)
  case int.compare(a_max, b_max) {
    order.Gt -> a
    order.Lt -> b
    order.Eq -> {
      // Prefer the list with more errors (more recovery = better match)
      case int.compare(list.length(a), list.length(b)) {
        order.Gt | order.Eq -> a
        order.Lt -> b
      }
    }
  }
}

/// Find the maximum error line across a list of parser errors.
fn max_error_line(errors: List(ParserError)) -> Int {
  list.fold(errors, 0, fn(acc, err) {
    int.max(acc, parser_error.error_line(err))
  })
}

/// Convert 1-indexed line to 0-indexed LSP line.
fn to_lsp_line(line: Int) -> Int {
  case line > 0 {
    True -> line - 1
    False -> 0
  }
}

/// Convert 1-indexed column to 0-indexed LSP character.
fn to_lsp_column(column: Int) -> Int {
  case column > 0 {
    True -> column - 1
    False -> 0
  }
}
