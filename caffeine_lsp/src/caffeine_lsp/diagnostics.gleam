import caffeine_lang/frontend/parser
import caffeine_lang/frontend/parser_error.{type ParserError}
import caffeine_lang/frontend/tokenizer_error.{type TokenizerError}
import caffeine_lang/frontend/validator.{type ValidatorError}
import gleam/bool
import gleam/string

/// A diagnostic to send to the editor.
pub type Diagnostic {
  Diagnostic(line: Int, column: Int, severity: Int, message: String)
}

/// LSP severity constants.
const severity_error = 1

const severity_warning = 2

/// Analyze source text and return diagnostics.
/// Tries to parse as blueprints first, then as expects.
/// If parsing succeeds, runs the validator for additional checks.
pub fn get_diagnostics(content: String) -> List(Diagnostic) {
  use <- bool.guard(when: string.trim(content) == "", return: [])
  case parser.parse_blueprints_file(content) {
    Ok(file) ->
      case validator.validate_blueprints_file(file) {
        Ok(_) -> []
        Error(err) -> [validator_error_to_diagnostic(content, err)]
      }
    Error(blueprint_err) ->
      case parser.parse_expects_file(content) {
        Ok(file) ->
          case validator.validate_expects_file(file) {
            Ok(_) -> []
            Error(err) -> [validator_error_to_diagnostic(content, err)]
          }
        Error(expects_err) -> {
          use <- bool.guard(
            when: string.starts_with(
              string.trim_start(content),
              "Expectations",
            ),
            return: [parser_error_to_diagnostic(expects_err)],
          )
          [parser_error_to_diagnostic(blueprint_err)]
        }
      }
  }
}

fn validator_error_to_diagnostic(
  content: String,
  err: ValidatorError,
) -> Diagnostic {
  case err {
    validator.DuplicateExtendable(name) -> {
      let #(line, col) = find_name_position(content, name)
      Diagnostic(
        line: line,
        column: col,
        severity: severity_error,
        message: "Duplicate extendable '" <> name <> "'",
      )
    }
    validator.UndefinedExtendable(name, referenced_by) -> {
      let #(line, col) = find_name_position(content, name)
      Diagnostic(
        line: line,
        column: col,
        severity: severity_error,
        message: "Undefined extendable '"
          <> name
          <> "' referenced by '"
          <> referenced_by
          <> "'",
      )
    }
    validator.DuplicateExtendsReference(name, referenced_by) -> {
      let #(line, col) = find_name_position(content, name)
      Diagnostic(
        line: line,
        column: col,
        severity: severity_warning,
        message: "Duplicate extends reference '"
          <> name
          <> "' in '"
          <> referenced_by
          <> "'",
      )
    }
    validator.InvalidExtendableKind(name, expected, got) -> {
      let #(line, col) = find_name_position(content, name)
      Diagnostic(
        line: line,
        column: col,
        severity: severity_error,
        message: "Extendable '"
          <> name
          <> "' must be "
          <> expected
          <> ", got "
          <> got,
      )
    }
    validator.UndefinedTypeAlias(name, referenced_by) -> {
      let #(line, col) = find_name_position(content, name)
      Diagnostic(
        line: line,
        column: col,
        severity: severity_error,
        message: "Undefined type alias '"
          <> name
          <> "' referenced by '"
          <> referenced_by
          <> "'",
      )
    }
    validator.DuplicateTypeAlias(name) -> {
      let #(line, col) = find_name_position(content, name)
      Diagnostic(
        line: line,
        column: col,
        severity: severity_error,
        message: "Duplicate type alias '" <> name <> "'",
      )
    }
    validator.CircularTypeAlias(name, cycle) -> {
      let #(line, col) = find_name_position(content, name)
      let cycle_str = string.join(cycle, " -> ")
      Diagnostic(
        line: line,
        column: col,
        severity: severity_error,
        message: "Circular type alias '" <> name <> "': " <> cycle_str,
      )
    }
    validator.InvalidDictKeyTypeAlias(alias_name, resolved_to, referenced_by) -> {
      let #(line, col) = find_name_position(content, alias_name)
      Diagnostic(
        line: line,
        column: col,
        severity: severity_error,
        message: "Dict key type '"
          <> alias_name
          <> "' resolves to '"
          <> resolved_to
          <> "' (must be String-based), in '"
          <> referenced_by
          <> "'",
      )
    }
    validator.ExtendableOvershadowing(field_name, item_name, extendable_name) -> {
      let #(line, col) = find_name_position(content, field_name)
      Diagnostic(
        line: line,
        column: col,
        severity: severity_error,
        message: "Field '"
          <> field_name
          <> "' in '"
          <> item_name
          <> "' overshadows field from extendable '"
          <> extendable_name
          <> "'",
      )
    }
  }
}

/// Find the 0-indexed line and column of the first occurrence of a name in source.
fn find_name_position(content: String, name: String) -> #(Int, Int) {
  let lines = string.split(content, "\n")
  find_in_lines(lines, name, 0)
}

fn find_in_lines(
  lines: List(String),
  name: String,
  line_idx: Int,
) -> #(Int, Int) {
  case lines {
    [] -> #(0, 0)
    [first, ..rest] -> {
      case string.contains(first, name) {
        True -> {
          let col = find_column(first, name, 0)
          #(line_idx, col)
        }
        False -> find_in_lines(rest, name, line_idx + 1)
      }
    }
  }
}

fn find_column(line: String, name: String, offset: Int) -> Int {
  case string.starts_with(line, name) {
    True -> offset
    False -> {
      case string.pop_grapheme(line) {
        Ok(#(_, rest)) -> find_column(rest, name, offset + 1)
        Error(_) -> 0
      }
    }
  }
}

fn parser_error_to_diagnostic(err: ParserError) -> Diagnostic {
  case err {
    parser_error.TokenizerError(tok_err) ->
      tokenizer_error_to_diagnostic(tok_err)
    parser_error.UnexpectedToken(expected, got, line, column) ->
      Diagnostic(
        line: to_lsp_line(line),
        column: to_lsp_column(column),
        severity: severity_error,
        message: "Unexpected token: expected "
          <> expected
          <> ", got "
          <> got,
      )
    parser_error.UnexpectedEOF(expected, line, column) ->
      Diagnostic(
        line: to_lsp_line(line),
        column: to_lsp_column(column),
        severity: severity_error,
        message: "Unexpected end of file: expected " <> expected,
      )
    parser_error.UnknownType(name, line, column) ->
      Diagnostic(
        line: to_lsp_line(line),
        column: to_lsp_column(column),
        severity: severity_error,
        message: "Unknown type '" <> name <> "'",
      )
    parser_error.InvalidRefinement(message, line, column) ->
      Diagnostic(
        line: to_lsp_line(line),
        column: to_lsp_column(column),
        severity: severity_error,
        message: "Invalid refinement: " <> message,
      )
    parser_error.QuotedFieldName(name, line, column) ->
      Diagnostic(
        line: to_lsp_line(line),
        column: to_lsp_column(column),
        severity: severity_error,
        message: "Field names should not be quoted. Use '"
          <> name
          <> "' instead",
      )
    parser_error.InvalidTypeAliasName(name, message, line, column) ->
      Diagnostic(
        line: to_lsp_line(line),
        column: to_lsp_column(column),
        severity: severity_error,
        message: "Invalid type alias name '" <> name <> "': " <> message,
      )
  }
}

fn tokenizer_error_to_diagnostic(err: TokenizerError) -> Diagnostic {
  case err {
    tokenizer_error.UnterminatedString(line, column) ->
      Diagnostic(
        line: to_lsp_line(line),
        column: to_lsp_column(column),
        severity: severity_error,
        message: "Unterminated string",
      )
    tokenizer_error.InvalidCharacter(line, column, char) ->
      Diagnostic(
        line: to_lsp_line(line),
        column: to_lsp_column(column),
        severity: severity_error,
        message: "Invalid character '" <> char <> "'",
      )
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
