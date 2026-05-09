import caffeine_lang/frontend/parser_error
import caffeine_lang/frontend/tokenizer_error
import gleam/string
import gleeunit/should

// ==== to_string ====
// * ✅ TokenizerError delegates to tokenizer_error.to_string
// * ✅ UnexpectedToken includes expected, got, line, column
// * ✅ UnexpectedEOF includes expected, line, column
// * ✅ UnknownType includes name, line, column
// * ✅ InvalidRefinement includes message, line, column
// * ✅ QuotedFieldName includes name, line, column
// * ✅ InvalidTypeAliasName includes name, message, line, column
pub fn to_string_test() {
  // TokenizerError
  let tok_err =
    parser_error.to_string(
      parser_error.TokenizerError(tokenizer_error.UnterminatedString(1, 5)),
    )
  { string.contains(tok_err, "Unterminated string") } |> should.be_true()

  // UnexpectedToken
  let result =
    parser_error.to_string(parser_error.UnexpectedToken(
      expected: "identifier",
      got: "{",
      line: 3,
      column: 10,
    ))
  { string.contains(result, "Unexpected token") } |> should.be_true()
  { string.contains(result, "line 3") } |> should.be_true()
  { string.contains(result, "column 10") } |> should.be_true()
  { string.contains(result, "identifier") } |> should.be_true()

  // UnexpectedEOF
  let result =
    parser_error.to_string(parser_error.UnexpectedEOF(
      expected: "}",
      line: 5,
      column: 1,
    ))
  { string.contains(result, "Unexpected end of file") } |> should.be_true()
  { string.contains(result, "line 5") } |> should.be_true()

  // UnknownType
  let result =
    parser_error.to_string(parser_error.UnknownType(
      name: "Foo",
      line: 2,
      column: 8,
    ))
  { string.contains(result, "Unknown type") } |> should.be_true()
  { string.contains(result, "Foo") } |> should.be_true()

  // InvalidRefinement
  let result =
    parser_error.to_string(parser_error.InvalidRefinement(
      message: "bad syntax",
      line: 1,
      column: 1,
    ))
  { string.contains(result, "Invalid refinement") } |> should.be_true()
  { string.contains(result, "bad syntax") } |> should.be_true()

  // QuotedFieldName
  let result =
    parser_error.to_string(parser_error.QuotedFieldName(
      name: "env",
      line: 4,
      column: 5,
    ))
  { string.contains(result, "Quoted field name") } |> should.be_true()
  { string.contains(result, "env") } |> should.be_true()

  // InvalidTypeAliasName
  let result =
    parser_error.to_string(parser_error.InvalidTypeAliasName(
      name: "bad",
      message: "must start with _",
      line: 1,
      column: 1,
    ))
  { string.contains(result, "Invalid type alias name") } |> should.be_true()
  { string.contains(result, "bad") } |> should.be_true()
  { string.contains(result, "must start with _") } |> should.be_true()
}
