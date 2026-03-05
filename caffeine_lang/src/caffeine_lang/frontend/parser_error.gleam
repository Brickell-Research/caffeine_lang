import caffeine_lang/frontend/tokenizer_error
import gleam/int

/// Errors that can occur during parsing.
pub type ParserError {
  TokenizerError(tokenizer_error.TokenizerError)
  UnexpectedToken(expected: String, got: String, line: Int, column: Int)
  UnexpectedEOF(expected: String, line: Int, column: Int)
  UnknownType(name: String, line: Int, column: Int)
  InvalidRefinement(message: String, line: Int, column: Int)
  QuotedFieldName(name: String, line: Int, column: Int)
  InvalidTypeAliasName(name: String, message: String, line: Int, column: Int)
}

/// Converts a parser error to a human-readable string.
pub fn to_string(err: ParserError) -> String {
  case err {
    TokenizerError(tok_err) -> tokenizer_error.to_string(tok_err)
    UnexpectedToken(expected, got, line, column) ->
      "Unexpected token at line "
      <> int.to_string(line)
      <> ", column "
      <> int.to_string(column)
      <> ": expected "
      <> expected
      <> ", got "
      <> got
    UnexpectedEOF(expected, line, column) ->
      "Unexpected end of file at line "
      <> int.to_string(line)
      <> ", column "
      <> int.to_string(column)
      <> ": expected "
      <> expected
    UnknownType(name, line, column) ->
      "Unknown type '"
      <> name
      <> "' at line "
      <> int.to_string(line)
      <> ", column "
      <> int.to_string(column)
    InvalidRefinement(message, line, column) ->
      "Invalid refinement at line "
      <> int.to_string(line)
      <> ", column "
      <> int.to_string(column)
      <> ": "
      <> message
    QuotedFieldName(name, line, column) ->
      "Quoted field name at line "
      <> int.to_string(line)
      <> ", column "
      <> int.to_string(column)
      <> ": field names should not be quoted. Use '"
      <> name
      <> "' instead of '\""
      <> name
      <> "\"'"
    InvalidTypeAliasName(name, message, line, column) ->
      "Invalid type alias name '"
      <> name
      <> "' at line "
      <> int.to_string(line)
      <> ", column "
      <> int.to_string(column)
      <> ": "
      <> message
  }
}

/// Extracts the line number from a parser error.
pub fn error_line(err: ParserError) -> Int {
  case err {
    TokenizerError(tok_err) ->
      case tok_err {
        tokenizer_error.UnterminatedString(line, _) -> line
        tokenizer_error.InvalidCharacter(line, _, _) -> line
      }
    UnexpectedToken(_, _, line, _) -> line
    UnexpectedEOF(_, line, _) -> line
    UnknownType(_, line, _) -> line
    InvalidRefinement(_, line, _) -> line
    QuotedFieldName(_, line, _) -> line
    InvalidTypeAliasName(_, _, line, _) -> line
  }
}

/// Extracts the column number from a parser error.
pub fn error_column(err: ParserError) -> Int {
  case err {
    TokenizerError(tok_err) ->
      case tok_err {
        tokenizer_error.UnterminatedString(_, column) -> column
        tokenizer_error.InvalidCharacter(_, column, _) -> column
      }
    UnexpectedToken(_, _, _, column) -> column
    UnexpectedEOF(_, _, column) -> column
    UnknownType(_, _, column) -> column
    InvalidRefinement(_, _, column) -> column
    QuotedFieldName(_, _, column) -> column
    InvalidTypeAliasName(_, _, _, column) -> column
  }
}
