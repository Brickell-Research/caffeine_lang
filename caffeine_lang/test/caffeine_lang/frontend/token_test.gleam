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
    #("keyword Blueprints", token.KeywordBlueprints, "Blueprints"),
    #("keyword Expectations", token.KeywordExpectations, "Expectations"),
    #("keyword for", token.KeywordFor, "for"),
    #("keyword extends", token.KeywordExtends, "extends"),
    #("keyword Requires", token.KeywordRequires, "Requires"),
    #("keyword Provides", token.KeywordProvides, "Provides"),
    #("keyword in", token.KeywordIn, "in"),
    #("keyword x", token.KeywordX, "x"),
    #("keyword String", token.KeywordString, "String"),
    #("keyword Integer", token.KeywordInteger, "Integer"),
    #("keyword Float", token.KeywordFloat, "Float"),
    #("keyword Boolean", token.KeywordBoolean, "Boolean"),
    #("keyword List", token.KeywordList, "List"),
    #("keyword Dict", token.KeywordDict, "Dict"),
    #("keyword Optional", token.KeywordOptional, "Optional"),
    #("keyword Defaulted", token.KeywordDefaulted, "Defaulted"),
    #("keyword Type", token.KeywordType, "Type"),
    #("keyword URL", token.KeywordURL, "URL"),
    // Literals
    #("literal string", token.LiteralString("hello"), "\"hello\""),
    #("literal integer", token.LiteralInteger(42), "integer"),
    #("literal float", token.LiteralFloat(3.14), "float"),
    #("literal true", token.LiteralTrue, "true"),
    #("literal false", token.LiteralFalse, "false"),
    // Symbols
    #("symbol left brace", token.SymbolLeftBrace, "{"),
    #("symbol right brace", token.SymbolRightBrace, "}"),
    #("symbol left paren", token.SymbolLeftParen, "("),
    #("symbol right paren", token.SymbolRightParen, ")"),
    #("symbol left bracket", token.SymbolLeftBracket, "["),
    #("symbol right bracket", token.SymbolRightBracket, "]"),
    #("symbol colon", token.SymbolColon, ":"),
    #("symbol comma", token.SymbolComma, ","),
    #("symbol star", token.SymbolStar, "*"),
    #("symbol plus", token.SymbolPlus, "+"),
    #("symbol pipe", token.SymbolPipe, "|"),
    #("symbol equals", token.SymbolEquals, "="),
    #("symbol dot dot", token.SymbolDotDot, ".."),
    // Whitespace
    #("whitespace newline", token.WhitespaceNewline, "newline"),
    #("whitespace indent", token.WhitespaceIndent(4), "indent"),
    // Comments
    #("comment line", token.CommentLine("test"), "comment"),
    #("comment section", token.CommentSection("test"), "section comment"),
    // Identifier
    #("identifier", token.Identifier("my_name"), "my_name"),
    // EOF
    #("EOF", token.EOF, "end of file"),
  ]
  |> test_helpers.table_test_1(token.to_string)
}
