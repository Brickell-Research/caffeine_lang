/// Errors that can occur during parsing.
pub type ParserError {
  UnexpectedToken(expected: String, got: String, line: Int, column: Int)
  UnexpectedEOF(expected: String, line: Int, column: Int)
  UnknownType(name: String, line: Int, column: Int)
  InvalidRefinement(message: String, line: Int, column: Int)
  EmptyFile(line: Int, column: Int)
}
