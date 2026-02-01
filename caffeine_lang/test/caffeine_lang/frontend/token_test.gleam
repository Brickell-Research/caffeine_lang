import caffeine_lang/frontend/token
import test_helpers

// ==== to_string ====
// * ✅ keywords
// * ✅ literals
// * ✅ symbols
// * ✅ whitespace
// * ✅ comments
// * ✅ identifier
// * ✅ EOF
pub fn to_string_test() {
  [
    // Keywords
    #(token.KeywordBlueprints, "Blueprints"),
    #(token.KeywordExpectations, "Expectations"),
    #(token.KeywordFor, "for"),
    #(token.KeywordExtends, "extends"),
    #(token.KeywordRequires, "Requires"),
    #(token.KeywordProvides, "Provides"),
    #(token.KeywordIn, "in"),
    #(token.KeywordX, "x"),
    #(token.KeywordString, "String"),
    #(token.KeywordInteger, "Integer"),
    #(token.KeywordFloat, "Float"),
    #(token.KeywordBoolean, "Boolean"),
    #(token.KeywordList, "List"),
    #(token.KeywordDict, "Dict"),
    #(token.KeywordOptional, "Optional"),
    #(token.KeywordDefaulted, "Defaulted"),
    #(token.KeywordType, "Type"),
    #(token.KeywordURL, "URL"),
    // Literals
    #(token.LiteralString("hello"), "\"hello\""),
    #(token.LiteralInteger(42), "integer"),
    #(token.LiteralFloat(3.14), "float"),
    #(token.LiteralTrue, "true"),
    #(token.LiteralFalse, "false"),
    // Symbols
    #(token.SymbolLeftBrace, "{"),
    #(token.SymbolRightBrace, "}"),
    #(token.SymbolLeftParen, "("),
    #(token.SymbolRightParen, ")"),
    #(token.SymbolLeftBracket, "["),
    #(token.SymbolRightBracket, "]"),
    #(token.SymbolColon, ":"),
    #(token.SymbolComma, ","),
    #(token.SymbolStar, "*"),
    #(token.SymbolPlus, "+"),
    #(token.SymbolPipe, "|"),
    #(token.SymbolEquals, "="),
    #(token.SymbolDotDot, ".."),
    // Whitespace
    #(token.WhitespaceNewline, "newline"),
    #(token.WhitespaceIndent(4), "indent"),
    // Comments
    #(token.CommentLine("test"), "comment"),
    #(token.CommentSection("test"), "section comment"),
    // Identifier
    #(token.Identifier("my_name"), "my_name"),
    // EOF
    #(token.EOF, "end of file"),
  ]
  |> test_helpers.array_based_test_executor_1(token.to_string)
}
