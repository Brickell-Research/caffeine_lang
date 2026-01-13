import caffeine_lang/frontend/token
import caffeine_lang/frontend/tokenizer
import caffeine_lang/frontend/tokenizer_error
import test_helpers

// ==== tokenize_keywords ====
// * ✅ Blueprints keyword
// * ✅ Expects keyword
// * ✅ for keyword
// * ✅ extends keyword
// * ✅ Requires keyword
// * ✅ Provides keyword
// * ✅ in keyword
// * ✅ x keyword
pub fn tokenize_keywords_test() {
  [
    #("Blueprints", Ok([token.KeywordBlueprints, token.EOF])),
    #("Expects", Ok([token.KeywordExpects, token.EOF])),
    #("for", Ok([token.KeywordFor, token.EOF])),
    #("extends", Ok([token.KeywordExtends, token.EOF])),
    #("Requires", Ok([token.KeywordRequires, token.EOF])),
    #("Provides", Ok([token.KeywordProvides, token.EOF])),
    #("in", Ok([token.KeywordIn, token.EOF])),
    #("x", Ok([token.KeywordX, token.EOF])),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_type_keywords ====
// * ✅ String type
// * ✅ Integer type
// * ✅ Float type
// * ✅ Boolean type
// * ✅ List type
// * ✅ Dict type
// * ✅ Optional type
// * ✅ Defaulted type
pub fn tokenize_type_keywords_test() {
  [
    #("String", Ok([token.KeywordString, token.EOF])),
    #("Integer", Ok([token.KeywordInteger, token.EOF])),
    #("Float", Ok([token.KeywordFloat, token.EOF])),
    #("Boolean", Ok([token.KeywordBoolean, token.EOF])),
    #("List", Ok([token.KeywordList, token.EOF])),
    #("Dict", Ok([token.KeywordDict, token.EOF])),
    #("Optional", Ok([token.KeywordOptional, token.EOF])),
    #("Defaulted", Ok([token.KeywordDefaulted, token.EOF])),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_string_literals ====
// * ✅ simple string
// * ✅ string with spaces
// * ✅ empty string
// * ✅ string with template variable
// * ✅ string with key-value template
// * ✅ string with negated template
// * ✅ complex query string
pub fn tokenize_string_literals_test() {
  [
    #("\"hello\"", Ok([token.LiteralString("hello"), token.EOF])),
    #("\"hello world\"", Ok([token.LiteralString("hello world"), token.EOF])),
    #("\"\"", Ok([token.LiteralString(""), token.EOF])),
    #("\"${env}\"", Ok([token.LiteralString("${env}"), token.EOF])),
    #("\"${env->env}\"", Ok([token.LiteralString("${env->env}"), token.EOF])),
    #(
      "\"${status->status.not}\"",
      Ok([token.LiteralString("${status->status.not}"), token.EOF]),
    ),
    #(
      "\"sum:http.requests{${env->env}, ${status->status.not}}\"",
      Ok([
        token.LiteralString(
          "sum:http.requests{${env->env}, ${status->status.not}}",
        ),
        token.EOF,
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_numeric_literals ====
// * ✅ positive integer
// * ✅ negative integer
// * ✅ zero integer
// * ✅ positive float
// * ✅ negative float
// * ✅ zero float
// * ✅ float with decimals
pub fn tokenize_numeric_literals_test() {
  [
    #("42", Ok([token.LiteralInteger(42), token.EOF])),
    #("-42", Ok([token.LiteralInteger(-42), token.EOF])),
    #("0", Ok([token.LiteralInteger(0), token.EOF])),
    #("3.14", Ok([token.LiteralFloat(3.14), token.EOF])),
    #("-3.14", Ok([token.LiteralFloat(-3.14), token.EOF])),
    #("0.0", Ok([token.LiteralFloat(0.0), token.EOF])),
    #("99.95", Ok([token.LiteralFloat(99.95), token.EOF])),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_boolean_literals ====
// * ✅ true literal
// * ✅ false literal
pub fn tokenize_boolean_literals_test() {
  [
    #("true", Ok([token.LiteralTrue, token.EOF])),
    #("false", Ok([token.LiteralFalse, token.EOF])),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_identifiers ====
// * ✅ simple identifier
// * ✅ underscore prefix
// * ✅ identifier with numbers
// * ✅ identifier with underscores
// * ✅ mixed case identifier
pub fn tokenize_identifiers_test() {
  [
    #("env", Ok([token.Identifier("env"), token.EOF])),
    #("_common", Ok([token.Identifier("_common"), token.EOF])),
    #("p99", Ok([token.Identifier("p99"), token.EOF])),
    #("api_availability", Ok([token.Identifier("api_availability"), token.EOF])),
    #("window_in_days", Ok([token.Identifier("window_in_days"), token.EOF])),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_symbols ====
// * ✅ left brace
// * ✅ right brace
// * ✅ left paren
// * ✅ right paren
// * ✅ left bracket
// * ✅ right bracket
// * ✅ colon
// * ✅ comma
// * ✅ star
// * ✅ plus
// * ✅ pipe
// * ✅ dot dot
pub fn tokenize_symbols_test() {
  [
    #("{", Ok([token.SymbolLeftBrace, token.EOF])),
    #("}", Ok([token.SymbolRightBrace, token.EOF])),
    #("(", Ok([token.SymbolLeftParen, token.EOF])),
    #(")", Ok([token.SymbolRightParen, token.EOF])),
    #("[", Ok([token.SymbolLeftBracket, token.EOF])),
    #("]", Ok([token.SymbolRightBracket, token.EOF])),
    #(":", Ok([token.SymbolColon, token.EOF])),
    #(",", Ok([token.SymbolComma, token.EOF])),
    #("*", Ok([token.SymbolStar, token.EOF])),
    #("+", Ok([token.SymbolPlus, token.EOF])),
    #("|", Ok([token.SymbolPipe, token.EOF])),
    #("..", Ok([token.SymbolDotDot, token.EOF])),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_whitespace ====
// * ✅ single newline
// * ✅ multiple newlines collapse
// * ✅ two space indent
// * ✅ four space indent
// * ✅ tab indent
// * ✅ trailing spaces ignored
pub fn tokenize_whitespace_test() {
  [
    #("\n", Ok([token.WhitespaceNewline, token.EOF])),
    #("\n\n\n", Ok([token.WhitespaceNewline, token.EOF])),
    #("  ", Ok([token.WhitespaceIndent(2), token.EOF])),
    #("    ", Ok([token.WhitespaceIndent(4), token.EOF])),
    #("\t", Ok([token.WhitespaceIndent(2), token.EOF])),
    #(
      "  env  ",
      Ok([token.WhitespaceIndent(2), token.Identifier("env"), token.EOF]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_comments ====
// * ✅ line comment
// * ✅ section comment
// * ✅ comment with newline
pub fn tokenize_comments_test() {
  [
    #(
      "# This is a comment",
      Ok([token.CommentLine(" This is a comment"), token.EOF]),
    ),
    #(
      "## API Availability",
      Ok([token.CommentSection(" API Availability"), token.EOF]),
    ),
    #(
      "# comment\n",
      Ok([token.CommentLine(" comment"), token.WhitespaceNewline, token.EOF]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_blueprint_header ====
// * ✅ single artifact header
// * ✅ multi-artifact header
pub fn tokenize_blueprint_header_test() {
  [
    #(
      "Blueprints for \"SLO\"",
      Ok([
        token.KeywordBlueprints,
        token.KeywordFor,
        token.LiteralString("SLO"),
        token.EOF,
      ]),
    ),
    #(
      "Blueprints for \"SLO\" + \"DependencyRelation\"",
      Ok([
        token.KeywordBlueprints,
        token.KeywordFor,
        token.LiteralString("SLO"),
        token.SymbolPlus,
        token.LiteralString("DependencyRelation"),
        token.EOF,
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_expects_header ====
// * ✅ expects header line
pub fn tokenize_expects_header_test() {
  [
    #(
      "Expects for \"api_availability\"",
      Ok([
        token.KeywordExpects,
        token.KeywordFor,
        token.LiteralString("api_availability"),
        token.EOF,
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_extendable ====
// * ✅ requires extendable
// * ✅ provides extendable
pub fn tokenize_extendable_test() {
  [
    #(
      "_common (Requires): { env: String }",
      Ok([
        token.Identifier("_common"),
        token.SymbolLeftParen,
        token.KeywordRequires,
        token.SymbolRightParen,
        token.SymbolColon,
        token.SymbolLeftBrace,
        token.Identifier("env"),
        token.SymbolColon,
        token.KeywordString,
        token.SymbolRightBrace,
        token.EOF,
      ]),
    ),
    #(
      "_base (Provides): { vendor: \"datadog\" }",
      Ok([
        token.Identifier("_base"),
        token.SymbolLeftParen,
        token.KeywordProvides,
        token.SymbolRightParen,
        token.SymbolColon,
        token.SymbolLeftBrace,
        token.Identifier("vendor"),
        token.SymbolColon,
        token.LiteralString("datadog"),
        token.SymbolRightBrace,
        token.EOF,
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_blueprint_item ====
// * ✅ item with extends
// * ✅ item without extends
pub fn tokenize_blueprint_item_test() {
  [
    #(
      "* \"api_availability\" extends [_base]:",
      Ok([
        token.SymbolStar,
        token.LiteralString("api_availability"),
        token.KeywordExtends,
        token.SymbolLeftBracket,
        token.Identifier("_base"),
        token.SymbolRightBracket,
        token.SymbolColon,
        token.EOF,
      ]),
    ),
    #(
      "* \"latency\":",
      Ok([
        token.SymbolStar,
        token.LiteralString("latency"),
        token.SymbolColon,
        token.EOF,
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_requires_block ====
// * ✅ multiple fields
pub fn tokenize_requires_block_test() {
  [
    #(
      "Requires { env: String, threshold: Float }",
      Ok([
        token.KeywordRequires,
        token.SymbolLeftBrace,
        token.Identifier("env"),
        token.SymbolColon,
        token.KeywordString,
        token.SymbolComma,
        token.Identifier("threshold"),
        token.SymbolColon,
        token.KeywordFloat,
        token.SymbolRightBrace,
        token.EOF,
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_provides_block ====
// * ✅ string and float values
pub fn tokenize_provides_block_test() {
  [
    #(
      "Provides { vendor: \"datadog\", threshold: 99.95 }",
      Ok([
        token.KeywordProvides,
        token.SymbolLeftBrace,
        token.Identifier("vendor"),
        token.SymbolColon,
        token.LiteralString("datadog"),
        token.SymbolComma,
        token.Identifier("threshold"),
        token.SymbolColon,
        token.LiteralFloat(99.95),
        token.SymbolRightBrace,
        token.EOF,
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_refinement_oneof ====
// * ✅ oneof with strings
pub fn tokenize_refinement_oneof_test() {
  [
    #(
      "String { x | x in { \"production\", \"staging\" } }",
      Ok([
        token.KeywordString,
        token.SymbolLeftBrace,
        token.KeywordX,
        token.SymbolPipe,
        token.KeywordX,
        token.KeywordIn,
        token.SymbolLeftBrace,
        token.LiteralString("production"),
        token.SymbolComma,
        token.LiteralString("staging"),
        token.SymbolRightBrace,
        token.SymbolRightBrace,
        token.EOF,
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_refinement_range ====
// * ✅ range with float bounds
pub fn tokenize_refinement_range_test() {
  [
    #(
      "Float { x | x in ( 0.0 .. 100.0 ) }",
      Ok([
        token.KeywordFloat,
        token.SymbolLeftBrace,
        token.KeywordX,
        token.SymbolPipe,
        token.KeywordX,
        token.KeywordIn,
        token.SymbolLeftParen,
        token.LiteralFloat(0.0),
        token.SymbolDotDot,
        token.LiteralFloat(100.0),
        token.SymbolRightParen,
        token.SymbolRightBrace,
        token.EOF,
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_errors ====
// * ✅ unterminated string
// * ✅ string with newline
// * ✅ invalid character @
// * ✅ invalid character $
// * ✅ single dot
// * ✅ error on line 2
// * ✅ error with indent
pub fn tokenize_errors_test() {
  [
    #("\"unterminated", Error(tokenizer_error.UnterminatedString(1, 1))),
    #("\"hello\nworld\"", Error(tokenizer_error.UnterminatedString(1, 1))),
    #("@", Error(tokenizer_error.InvalidCharacter(1, 1, "@"))),
    #("$", Error(tokenizer_error.InvalidCharacter(1, 1, "$"))),
    #(".", Error(tokenizer_error.InvalidCharacter(1, 1, "."))),
    #("env\n@", Error(tokenizer_error.InvalidCharacter(2, 1, "@"))),
    #("env\n  @", Error(tokenizer_error.InvalidCharacter(2, 3, "@"))),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_multiline ====
// * ✅ full blueprint structure
pub fn tokenize_multiline_test() {
  [
    #(
      "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }",
      Ok([
        token.KeywordBlueprints,
        token.KeywordFor,
        token.LiteralString("SLO"),
        token.WhitespaceNewline,
        token.WhitespaceIndent(2),
        token.SymbolStar,
        token.LiteralString("api"),
        token.SymbolColon,
        token.WhitespaceNewline,
        token.WhitespaceIndent(4),
        token.KeywordRequires,
        token.SymbolLeftBrace,
        token.Identifier("env"),
        token.SymbolColon,
        token.KeywordString,
        token.SymbolRightBrace,
        token.EOF,
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}

// ==== tokenize_edge_cases ====
// * ✅ empty input
// * ✅ integer range
// * ✅ mixed indent
// * ✅ tab mid-line
// * ✅ comment at EOF
// * ✅ multiple extends
// * ✅ integer-only range
pub fn tokenize_edge_cases_test() {
  [
    #("", Ok([token.EOF])),
    #(
      "1..10",
      Ok([
        token.LiteralInteger(1),
        token.SymbolDotDot,
        token.LiteralInteger(10),
        token.EOF,
      ]),
    ),
    #("\t  x", Ok([token.WhitespaceIndent(4), token.KeywordX, token.EOF])),
    #(
      "env\tString",
      Ok([token.Identifier("env"), token.KeywordString, token.EOF]),
    ),
    #(
      "env # comment",
      Ok([token.Identifier("env"), token.CommentLine(" comment"), token.EOF]),
    ),
    #(
      "extends [_a, _b]",
      Ok([
        token.KeywordExtends,
        token.SymbolLeftBracket,
        token.Identifier("_a"),
        token.SymbolComma,
        token.Identifier("_b"),
        token.SymbolRightBracket,
        token.EOF,
      ]),
    ),
    #(
      "0..100",
      Ok([
        token.LiteralInteger(0),
        token.SymbolDotDot,
        token.LiteralInteger(100),
        token.EOF,
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenizer.tokenize)
}
