import caffeine_lang/frontend/ast.{
  type BlueprintsFile, type ExpectsBlock, type ExpectsFile, type Struct,
}
import caffeine_lang/frontend/parser_error.{type ParserError}
import caffeine_lang/frontend/tokenizer_error.{type TokenizerError}
import caffeine_lang/frontend/validator.{type ValidatorError}
import caffeine_lsp/file_utils
import caffeine_lsp/lsp_types.{DsError, DsWarning}
import caffeine_lsp/position_utils
import gleam/bool
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// Structured diagnostic codes for machine-readable identification.
pub type DiagnosticCode {
  QuotedFieldName
  BlueprintNotFound
  DependencyNotFound
  NoDiagnosticCode
}

/// Converts a DiagnosticCode to its wire-format string, if applicable.
pub fn diagnostic_code_to_string(code: DiagnosticCode) -> Option(String) {
  case code {
    QuotedFieldName -> option.Some("quoted-field-name")
    BlueprintNotFound -> option.Some("blueprint-not-found")
    DependencyNotFound -> option.Some("dependency-not-found")
    NoDiagnosticCode -> option.None
  }
}

/// A diagnostic to send to the editor.
pub type Diagnostic {
  Diagnostic(
    line: Int,
    column: Int,
    end_column: Int,
    severity: Int,
    message: String,
    code: DiagnosticCode,
  )
}

/// Analyze source text and return diagnostics.
/// Tries to parse as blueprints first, then as expects.
/// If parsing succeeds, runs the validator for additional checks.
pub fn get_diagnostics(content: String) -> List(Diagnostic) {
  use <- bool.guard(when: string.trim(content) == "", return: [])
  case file_utils.parse(content) {
    Ok(file_utils.Blueprints(file)) ->
      case validator.validate_blueprints_file(file) {
        Ok(_) -> []
        Error(errs) -> list.map(errs, validator_error_to_diagnostic(content, _))
      }
    Ok(file_utils.Expects(file)) ->
      case validator.validate_expects_file(file) {
        Ok(_) -> []
        Error(errs) -> list.map(errs, validator_error_to_diagnostic(content, _))
      }
    Error(#(blueprint_err, expects_err)) -> {
      use <- bool.guard(
        when: string.starts_with(string.trim_start(content), "Expectations"),
        return: [parser_error_to_diagnostic(expects_err)],
      )
      [parser_error_to_diagnostic(blueprint_err)]
    }
  }
}

/// Check blueprint references in an expects file against known workspace blueprints.
/// Returns diagnostics for any blueprint refs not found in the known list.
pub fn get_cross_file_diagnostics(
  content: String,
  known_blueprints: List(String),
) -> List(Diagnostic) {
  use <- bool.guard(when: string.trim(content) == "", return: [])
  case file_utils.parse(content) {
    Ok(file_utils.Expects(file)) ->
      file.blocks
      |> list.filter_map(fn(block) {
        check_blueprint_ref(content, block, known_blueprints)
      })
    _ -> []
  }
}

/// Check a single expects block's blueprint reference against known blueprints.
fn check_blueprint_ref(
  content: String,
  block: ExpectsBlock,
  known_blueprints: List(String),
) -> Result(Diagnostic, Nil) {
  use <- bool.guard(
    when: list.contains(known_blueprints, block.blueprint),
    return: Error(Nil),
  )
  let #(line, col) = position_utils.find_name_position(content, block.blueprint)
  Ok(Diagnostic(
    line: line,
    column: col,
    end_column: col + string.length(block.blueprint),
    severity: lsp_types.diagnostic_severity_to_int(DsError),
    message: "Blueprint '" <> block.blueprint <> "' not found in workspace",
    code: BlueprintNotFound,
  ))
}

/// Check dependency relation targets against known expectation identifiers.
/// Returns diagnostics for any dependency targets not found in the known list.
pub fn get_cross_file_dependency_diagnostics(
  content: String,
  known_identifiers: List(String),
) -> List(Diagnostic) {
  use <- bool.guard(when: string.trim(content) == "", return: [])
  case file_utils.parse(content) {
    Ok(parsed) -> {
      let targets = extract_relation_targets(parsed)
      targets
      |> list.filter_map(fn(target) {
        check_dependency_ref(content, target, known_identifiers)
      })
    }
    Error(_) -> []
  }
}

/// Extract all dependency target strings from relation fields in a parsed file.
fn extract_relation_targets(parsed: file_utils.ParsedFile) -> List(String) {
  case parsed {
    file_utils.Blueprints(file) ->
      extract_relation_targets_from_blueprints(file)
    file_utils.Expects(file) -> extract_relation_targets_from_expects(file)
  }
}

fn extract_relation_targets_from_blueprints(
  file: BlueprintsFile,
) -> List(String) {
  file.blocks
  |> list.flat_map(fn(block) {
    block.items
    |> list.flat_map(fn(item) {
      extract_relation_targets_from_struct(item.provides)
    })
  })
}

fn extract_relation_targets_from_expects(file: ExpectsFile) -> List(String) {
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
  let #(line, col) = position_utils.find_name_position(content, target)
  Ok(Diagnostic(
    line: line,
    column: col,
    end_column: col + string.length(target),
    severity: lsp_types.diagnostic_severity_to_int(DsError),
    message: "Dependency '" <> target <> "' not found in workspace",
    code: DependencyNotFound,
  ))
}

/// Build a diagnostic at the position of a name in the source.
fn name_diagnostic(
  content: String,
  name: String,
  severity: Int,
  message: String,
) -> Diagnostic {
  let #(line, col) = position_utils.find_name_position(content, name)
  Diagnostic(
    line: line,
    column: col,
    end_column: col + string.length(name),
    severity: severity,
    message: message,
    code: NoDiagnosticCode,
  )
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
        lsp_types.diagnostic_severity_to_int(DsError),
        "Duplicate extendable '" <> name <> "'",
      )
    validator.UndefinedExtendable(name, referenced_by, _candidates) ->
      name_diagnostic(
        content,
        name,
        lsp_types.diagnostic_severity_to_int(DsError),
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
        lsp_types.diagnostic_severity_to_int(DsWarning),
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
        lsp_types.diagnostic_severity_to_int(DsError),
        "Extendable '" <> name <> "' must be " <> expected <> ", got " <> got,
      )
    validator.UndefinedTypeAlias(name, referenced_by, _candidates) ->
      name_diagnostic(
        content,
        name,
        lsp_types.diagnostic_severity_to_int(DsError),
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
        lsp_types.diagnostic_severity_to_int(DsError),
        "Duplicate type alias '" <> name <> "'",
      )
    validator.CircularTypeAlias(name, cycle) -> {
      let cycle_str = string.join(cycle, " -> ")
      name_diagnostic(
        content,
        name,
        lsp_types.diagnostic_severity_to_int(DsError),
        "Circular type alias '" <> name <> "': " <> cycle_str,
      )
    }
    validator.InvalidDictKeyTypeAlias(alias_name, resolved_to, referenced_by) ->
      name_diagnostic(
        content,
        alias_name,
        lsp_types.diagnostic_severity_to_int(DsError),
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
        lsp_types.diagnostic_severity_to_int(DsError),
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
        lsp_types.diagnostic_severity_to_int(DsError),
        "Name '" <> name <> "' is used as both an extendable and a type alias",
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
        severity: lsp_types.diagnostic_severity_to_int(DsError),
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
        severity: lsp_types.diagnostic_severity_to_int(DsError),
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
        severity: lsp_types.diagnostic_severity_to_int(DsError),
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
        severity: lsp_types.diagnostic_severity_to_int(DsError),
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
        severity: lsp_types.diagnostic_severity_to_int(DsError),
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
        severity: lsp_types.diagnostic_severity_to_int(DsError),
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
        severity: lsp_types.diagnostic_severity_to_int(DsError),
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
        severity: lsp_types.diagnostic_severity_to_int(DsError),
        message: "Invalid character '" <> char <> "'",
        code: NoDiagnosticCode,
      )
    }
  }
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
