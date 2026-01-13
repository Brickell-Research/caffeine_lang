/// Errors that can occur during tokenization.
pub type TokenizerError {
  UnterminatedString(line: Int, column: Int)
  InvalidCharacter(line: Int, column: Int, char: String)
}
