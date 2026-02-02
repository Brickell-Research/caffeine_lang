import caffeine_lang/frontend/parser_error.{type ParserError}
import caffeine_lang/frontend/tokenizer_error.{type TokenizerError}
import caffeine_lang/frontend/validator.{type ValidatorError}
import caffeine_lsp/file_utils
import caffeine_lsp/position_utils
import gleam/bool
import gleam/string

/// A diagnostic to send to the editor.
pub type Diagnostic {
  Diagnostic(
    line: Int,
    column: Int,
    end_column: Int,
    severity: Int,
    message: String,
  )
}

/// LSP severity constants.
const severity_error = 1

const severity_warning = 2

/// Analyze source text and return diagnostics.
/// Tries to parse as blueprints first, then as expects.
/// If parsing succeeds, runs the validator for additional checks.
pub fn get_diagnostics(content: String) -> List(Diagnostic) {
  use <- bool.guard(when: string.trim(content) == "", return: [])
  case file_utils.parse(content) {
    Ok(file_utils.Blueprints(file)) ->
      case validator.validate_blueprints_file(file) {
        Ok(_) -> []
        Error(err) -> [validator_error_to_diagnostic(content, err)]
      }
    Ok(file_utils.Expects(file)) ->
      case validator.validate_expects_file(file) {
        Ok(_) -> []
        Error(err) -> [validator_error_to_diagnostic(content, err)]
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
        severity_error,
        "Duplicate extendable '" <> name <> "'",
      )
    validator.UndefinedExtendable(name, referenced_by) ->
      name_diagnostic(
        content,
        name,
        severity_error,
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
        severity_warning,
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
        severity_error,
        "Extendable '" <> name <> "' must be " <> expected <> ", got " <> got,
      )
    validator.UndefinedTypeAlias(name, referenced_by) ->
      name_diagnostic(
        content,
        name,
        severity_error,
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
        severity_error,
        "Duplicate type alias '" <> name <> "'",
      )
    validator.CircularTypeAlias(name, cycle) -> {
      let cycle_str = string.join(cycle, " -> ")
      name_diagnostic(
        content,
        name,
        severity_error,
        "Circular type alias '" <> name <> "': " <> cycle_str,
      )
    }
    validator.InvalidDictKeyTypeAlias(alias_name, resolved_to, referenced_by) ->
      name_diagnostic(
        content,
        alias_name,
        severity_error,
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
        severity_error,
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
        severity_error,
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
        severity: severity_error,
        message: "Unexpected token: expected " <> expected <> ", got " <> got,
      )
    }
    parser_error.UnexpectedEOF(expected, line, column) -> {
      let col = to_lsp_column(column)
      Diagnostic(
        line: to_lsp_line(line),
        column: col,
        end_column: col + 1,
        severity: severity_error,
        message: "Unexpected end of file: expected " <> expected,
      )
    }
    parser_error.UnknownType(name, line, column) -> {
      let col = to_lsp_column(column)
      Diagnostic(
        line: to_lsp_line(line),
        column: col,
        end_column: col + string.length(name),
        severity: severity_error,
        message: "Unknown type '" <> name <> "'",
      )
    }
    parser_error.InvalidRefinement(message, line, column) -> {
      let col = to_lsp_column(column)
      Diagnostic(
        line: to_lsp_line(line),
        column: col,
        end_column: col + 1,
        severity: severity_error,
        message: "Invalid refinement: " <> message,
      )
    }
    parser_error.QuotedFieldName(name, line, column) -> {
      let col = to_lsp_column(column)
      Diagnostic(
        line: to_lsp_line(line),
        column: col,
        end_column: col + string.length(name) + 2,
        severity: severity_error,
        message: "Field names should not be quoted. Use '"
          <> name
          <> "' instead",
      )
    }
    parser_error.InvalidTypeAliasName(name, message, line, column) -> {
      let col = to_lsp_column(column)
      Diagnostic(
        line: to_lsp_line(line),
        column: col,
        end_column: col + string.length(name),
        severity: severity_error,
        message: "Invalid type alias name '" <> name <> "': " <> message,
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
        severity: severity_error,
        message: "Unterminated string",
      )
    }
    tokenizer_error.InvalidCharacter(line, column, char) -> {
      let col = to_lsp_column(column)
      Diagnostic(
        line: to_lsp_line(line),
        column: col,
        end_column: col + string.length(char),
        severity: severity_error,
        message: "Invalid character '" <> char <> "'",
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
