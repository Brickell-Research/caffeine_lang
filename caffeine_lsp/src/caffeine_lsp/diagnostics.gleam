import caffeine_lang/frontend/parser
import caffeine_lang/frontend/parser_error.{type ParserError}
import caffeine_lang/frontend/tokenizer_error.{type TokenizerError}
import gleam/string

/// A diagnostic to send to the editor.
pub type Diagnostic {
  Diagnostic(line: Int, column: Int, severity: Int, message: String)
}

/// LSP severity constants.
const severity_error = 1

/// Analyze source text and return diagnostics.
/// Tries to parse as blueprints first, then as expects.
pub fn get_diagnostics(content: String) -> List(Diagnostic) {
  case string.trim(content) {
    "" -> []
    _ -> {
      case parser.parse_blueprints_file(content) {
        Ok(_) -> []
        Error(blueprint_err) -> {
          case parser.parse_expects_file(content) {
            Ok(_) -> []
            Error(expects_err) -> {
              // Report the error from the relevant parser based on file content
              case string.starts_with(string.trim_start(content), "Expectations") {
                True -> [parser_error_to_diagnostic(expects_err)]
                False -> [parser_error_to_diagnostic(blueprint_err)]
              }
            }
          }
        }
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
    parser_error.EmptyFile(line, column) ->
      Diagnostic(
        line: to_lsp_line(line),
        column: to_lsp_column(column),
        severity: severity_error,
        message: "Empty file",
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
