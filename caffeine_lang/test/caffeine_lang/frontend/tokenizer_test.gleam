import caffeine_lang/frontend/token.{type Token}
import caffeine_lang/frontend/tokenizer
import caffeine_lang/frontend/tokenizer_error
import gleam/list
import gleam/result
import test_helpers

/// Strip position info from tokenizer output for tests that only care about token types.
fn tokenize_tokens(
  source: String,
) -> Result(List(Token), tokenizer_error.TokenizerError) {
  tokenizer.tokenize(source)
  |> result.map(list.map(_, fn(pt) { pt.token }))
}

// ==== tokenize_keywords ====
// * ✅ Blueprints keyword
// * ✅ Expects keyword
// * ✅ for keyword
// * ✅ extends keyword
// * ✅ Requires keyword
// * ✅ Provides keyword
// * ✅ Type keyword
// * ✅ in keyword
// * ✅ x keyword
pub fn tokenize_keywords_test() {
  [
    #(
      "Blueprints keyword",
      "Blueprints",
      Ok([token.KeywordBlueprints, token.EOF]),
    ),
    #(
      "Expects keyword",
      "Expectations",
      Ok([token.KeywordExpectations, token.EOF]),
    ),
    #("for keyword", "for", Ok([token.KeywordFor, token.EOF])),
    #("extends keyword", "extends", Ok([token.KeywordExtends, token.EOF])),
    #("Requires keyword", "Requires", Ok([token.KeywordRequires, token.EOF])),
    #("Provides keyword", "Provides", Ok([token.KeywordProvides, token.EOF])),
    #("Type keyword", "Type", Ok([token.KeywordType, token.EOF])),
    #("in keyword", "in", Ok([token.KeywordIn, token.EOF])),
    #("x keyword", "x", Ok([token.KeywordX, token.EOF])),
  ]
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
}

// ==== tokenize_type_keywords ====
// * ✅ String type
// * ✅ Integer type
// * ✅ Float type
// * ✅ Boolean type
// * ✅ URL type
// * ✅ List type
// * ✅ Dict type
// * ✅ Optional type
// * ✅ Defaulted type
// * ✅ Percentage type
pub fn tokenize_type_keywords_test() {
  [
    #("String type", "String", Ok([token.KeywordString, token.EOF])),
    #("Integer type", "Integer", Ok([token.KeywordInteger, token.EOF])),
    #("Float type", "Float", Ok([token.KeywordFloat, token.EOF])),
    #("Boolean type", "Boolean", Ok([token.KeywordBoolean, token.EOF])),
    #("URL type", "URL", Ok([token.KeywordURL, token.EOF])),
    #("List type", "List", Ok([token.KeywordList, token.EOF])),
    #("Dict type", "Dict", Ok([token.KeywordDict, token.EOF])),
    #("Optional type", "Optional", Ok([token.KeywordOptional, token.EOF])),
    #("Defaulted type", "Defaulted", Ok([token.KeywordDefaulted, token.EOF])),
    #("Percentage type", "Percentage", Ok([token.KeywordPercentage, token.EOF])),
  ]
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
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
    #(
      "simple string",
      "\"hello\"",
      Ok([token.LiteralString("hello"), token.EOF]),
    ),
    #(
      "string with spaces",
      "\"hello world\"",
      Ok([token.LiteralString("hello world"), token.EOF]),
    ),
    #("empty string", "\"\"", Ok([token.LiteralString(""), token.EOF])),
    #(
      "string with template variable",
      "\"${env}\"",
      Ok([token.LiteralString("${env}"), token.EOF]),
    ),
    #(
      "string with key-value template",
      "\"${env->env}\"",
      Ok([token.LiteralString("${env->env}"), token.EOF]),
    ),
    #(
      "string with negated template",
      "\"${status->status.not}\"",
      Ok([token.LiteralString("${status->status.not}"), token.EOF]),
    ),
    #(
      "complex query string",
      "\"sum:http.requests{${env->env}, ${status->status.not}}\"",
      Ok([
        token.LiteralString(
          "sum:http.requests{${env->env}, ${status->status.not}}",
        ),
        token.EOF,
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
}

// ==== tokenize_numeric_literals ====
// * ✅ positive integer
// * ✅ negative integer
// * ✅ zero integer
// * ✅ positive float
// * ✅ negative float
// * ✅ zero float
// * ✅ float with decimals
// * ✅ percentage from float
// * ✅ percentage from integer
// * ✅ zero percentage
pub fn tokenize_numeric_literals_test() {
  [
    #("positive integer", "42", Ok([token.LiteralInteger(42), token.EOF])),
    #("negative integer", "-42", Ok([token.LiteralInteger(-42), token.EOF])),
    #("zero integer", "0", Ok([token.LiteralInteger(0), token.EOF])),
    #("positive float", "3.14", Ok([token.LiteralFloat(3.14), token.EOF])),
    #("negative float", "-3.14", Ok([token.LiteralFloat(-3.14), token.EOF])),
    #("zero float", "0.0", Ok([token.LiteralFloat(0.0), token.EOF])),
    #(
      "float with decimals",
      "99.95",
      Ok([token.LiteralFloat(99.95), token.EOF]),
    ),
    #(
      "percentage from float",
      "99.9%",
      Ok([token.LiteralPercentage(99.9), token.EOF]),
    ),
    #(
      "percentage from integer",
      "100%",
      Ok([token.LiteralPercentage(100.0), token.EOF]),
    ),
    #("zero percentage", "0%", Ok([token.LiteralPercentage(0.0), token.EOF])),
  ]
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
}

// ==== tokenize_boolean_literals ====
// * ✅ true literal
// * ✅ false literal
pub fn tokenize_boolean_literals_test() {
  [
    #("true literal", "true", Ok([token.LiteralTrue, token.EOF])),
    #("false literal", "false", Ok([token.LiteralFalse, token.EOF])),
  ]
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
}

// ==== tokenize_identifiers ====
// * ✅ simple identifier
// * ✅ underscore prefix
// * ✅ identifier with numbers
// * ✅ identifier with underscores
// * ✅ mixed case identifier
pub fn tokenize_identifiers_test() {
  [
    #("simple identifier", "env", Ok([token.Identifier("env"), token.EOF])),
    #(
      "underscore prefix",
      "_common",
      Ok([token.Identifier("_common"), token.EOF]),
    ),
    #(
      "identifier with numbers",
      "p99",
      Ok([token.Identifier("p99"), token.EOF]),
    ),
    #(
      "identifier with underscores",
      "api_availability",
      Ok([token.Identifier("api_availability"), token.EOF]),
    ),
    #(
      "mixed case identifier",
      "window_in_days",
      Ok([token.Identifier("window_in_days"), token.EOF]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
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
    #("left brace", "{", Ok([token.SymbolLeftBrace, token.EOF])),
    #("right brace", "}", Ok([token.SymbolRightBrace, token.EOF])),
    #("left paren", "(", Ok([token.SymbolLeftParen, token.EOF])),
    #("right paren", ")", Ok([token.SymbolRightParen, token.EOF])),
    #("left bracket", "[", Ok([token.SymbolLeftBracket, token.EOF])),
    #("right bracket", "]", Ok([token.SymbolRightBracket, token.EOF])),
    #("colon", ":", Ok([token.SymbolColon, token.EOF])),
    #("comma", ",", Ok([token.SymbolComma, token.EOF])),
    #("star", "*", Ok([token.SymbolStar, token.EOF])),
    #("plus", "+", Ok([token.SymbolPlus, token.EOF])),
    #("pipe", "|", Ok([token.SymbolPipe, token.EOF])),
    #("dot dot", "..", Ok([token.SymbolDotDot, token.EOF])),
  ]
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
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
    #("single newline", "\n", Ok([token.WhitespaceNewline, token.EOF])),
    #(
      "multiple newlines collapse",
      "\n\n\n",
      Ok([token.WhitespaceNewline, token.EOF]),
    ),
    #("two space indent", "  ", Ok([token.WhitespaceIndent(2), token.EOF])),
    #("four space indent", "    ", Ok([token.WhitespaceIndent(4), token.EOF])),
    #("tab indent", "\t", Ok([token.WhitespaceIndent(2), token.EOF])),
    #(
      "trailing spaces ignored",
      "  env  ",
      Ok([token.WhitespaceIndent(2), token.Identifier("env"), token.EOF]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
}

// ==== tokenize_comments ====
// * ✅ line comment
// * ✅ section comment
// * ✅ comment with newline
pub fn tokenize_comments_test() {
  [
    #(
      "line comment",
      "# This is a comment",
      Ok([token.CommentLine(" This is a comment"), token.EOF]),
    ),
    #(
      "section comment",
      "## API Availability",
      Ok([token.CommentSection(" API Availability"), token.EOF]),
    ),
    #(
      "comment with newline",
      "# comment\n",
      Ok([token.CommentLine(" comment"), token.WhitespaceNewline, token.EOF]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
}

// ==== tokenize_blueprint_header ====
// * ✅ single artifact header
// * ✅ multi-artifact header
pub fn tokenize_blueprint_header_test() {
  [
    #(
      "single artifact header",
      "Blueprints for \"SLO\"",
      Ok([
        token.KeywordBlueprints,
        token.KeywordFor,
        token.LiteralString("SLO"),
        token.EOF,
      ]),
    ),
    #(
      "multi-artifact header",
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
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
}

// ==== tokenize_expects_header ====
// * ✅ expects header line
pub fn tokenize_expects_header_test() {
  [
    #(
      "expects header line",
      "Expectations for \"api_availability\"",
      Ok([
        token.KeywordExpectations,
        token.KeywordFor,
        token.LiteralString("api_availability"),
        token.EOF,
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
}

// ==== tokenize_extendable ====
// * ✅ requires extendable
// * ✅ provides extendable
pub fn tokenize_extendable_test() {
  [
    #(
      "requires extendable",
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
      "provides extendable",
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
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
}

// ==== tokenize_blueprint_item ====
// * ✅ item with extends
// * ✅ item without extends
pub fn tokenize_blueprint_item_test() {
  [
    #(
      "item with extends",
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
      "item without extends",
      "* \"latency\":",
      Ok([
        token.SymbolStar,
        token.LiteralString("latency"),
        token.SymbolColon,
        token.EOF,
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
}

// ==== tokenize_requires_block ====
// * ✅ multiple fields
pub fn tokenize_requires_block_test() {
  [
    #(
      "multiple fields",
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
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
}

// ==== tokenize_provides_block ====
// * ✅ string and float values
pub fn tokenize_provides_block_test() {
  [
    #(
      "string and float values",
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
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
}

// ==== tokenize_refinement_oneof ====
// * ✅ oneof with strings
pub fn tokenize_refinement_oneof_test() {
  [
    #(
      "oneof with strings",
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
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
}

// ==== tokenize_refinement_range ====
// * ✅ range with float bounds
pub fn tokenize_refinement_range_test() {
  [
    #(
      "range with float bounds",
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
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
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
    #(
      "unterminated string",
      "\"unterminated",
      Error(tokenizer_error.UnterminatedString(1, 1)),
    ),
    #(
      "string with newline",
      "\"hello\nworld\"",
      Error(tokenizer_error.UnterminatedString(1, 1)),
    ),
    #(
      "invalid character @",
      "@",
      Error(tokenizer_error.InvalidCharacter(1, 1, "@")),
    ),
    #(
      "invalid character $",
      "$",
      Error(tokenizer_error.InvalidCharacter(1, 1, "$")),
    ),
    #("single dot", ".", Error(tokenizer_error.InvalidCharacter(1, 1, "."))),
    #(
      "error on line 2",
      "env\n@",
      Error(tokenizer_error.InvalidCharacter(2, 1, "@")),
    ),
    #(
      "error with indent",
      "env\n  @",
      Error(tokenizer_error.InvalidCharacter(2, 3, "@")),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
}

// ==== tokenize_multiline ====
// * ✅ full blueprint structure
pub fn tokenize_multiline_test() {
  [
    #(
      "full blueprint structure",
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
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
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
    #("empty input", "", Ok([token.EOF])),
    #(
      "integer range",
      "1..10",
      Ok([
        token.LiteralInteger(1),
        token.SymbolDotDot,
        token.LiteralInteger(10),
        token.EOF,
      ]),
    ),
    #(
      "mixed indent",
      "\t  x",
      Ok([token.WhitespaceIndent(4), token.KeywordX, token.EOF]),
    ),
    #(
      "tab mid-line",
      "env\tString",
      Ok([token.Identifier("env"), token.KeywordString, token.EOF]),
    ),
    #(
      "comment at EOF",
      "env # comment",
      Ok([token.Identifier("env"), token.CommentLine(" comment"), token.EOF]),
    ),
    #(
      "multiple extends",
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
      "integer-only range",
      "0..100",
      Ok([
        token.LiteralInteger(0),
        token.SymbolDotDot,
        token.LiteralInteger(100),
        token.EOF,
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(tokenize_tokens)
}
