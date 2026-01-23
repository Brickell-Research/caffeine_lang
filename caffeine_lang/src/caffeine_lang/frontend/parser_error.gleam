import caffeine_lang/frontend/tokenizer_error
import gleam/int

/// Errors that can occur during parsing.
pub type ParserError {
  TokenizerError(tokenizer_error.TokenizerError)
  UnexpectedToken(expected: String, got: String, line: Int, column: Int)
  UnexpectedEOF(expected: String, line: Int, column: Int)
  UnknownType(name: String, line: Int, column: Int)
  InvalidRefinement(message: String, line: Int, column: Int)
  EmptyFile(line: Int, column: Int)
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
    EmptyFile(line, column) ->
      "Empty file at line "
      <> int.to_string(line)
      <> ", column "
      <> int.to_string(column)
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
