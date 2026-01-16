import gleam/int

/// Errors that can occur during tokenization.
pub type TokenizerError {
  UnterminatedString(line: Int, column: Int)
  InvalidCharacter(line: Int, column: Int, char: String)
}

/// Converts a tokenizer error to a human-readable string.
@internal
pub fn to_string(err: TokenizerError) -> String {
  case err {
    UnterminatedString(line, column) ->
      "Unterminated string at line "
      <> int.to_string(line)
      <> ", column "
      <> int.to_string(column)
    InvalidCharacter(line, column, char) ->
      "Invalid character '"
      <> char
      <> "' at line "
      <> int.to_string(line)
      <> ", column "
      <> int.to_string(column)
  }
}
