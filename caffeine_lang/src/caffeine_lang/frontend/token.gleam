/// A token produced by the tokenizer.
pub type Token {
  KeywordBlueprints
  KeywordExpectations
  KeywordFor
  KeywordExtends
  KeywordRequires
  KeywordProvides
  KeywordIn
  KeywordX
  KeywordString
  KeywordInteger
  KeywordFloat
  KeywordBoolean
  KeywordList
  KeywordDict
  KeywordOptional
  KeywordDefaulted
  LiteralString(String)
  LiteralInteger(Int)
  LiteralFloat(Float)
  LiteralTrue
  LiteralFalse
  SymbolLeftBrace
  SymbolRightBrace
  SymbolLeftParen
  SymbolRightParen
  SymbolLeftBracket
  SymbolRightBracket
  SymbolColon
  SymbolComma
  SymbolStar
  SymbolPlus
  SymbolPipe
  SymbolEquals
  SymbolDotDot
  WhitespaceNewline
  WhitespaceIndent(Int)
  CommentLine(String)
  CommentSection(String)
  Identifier(String)
  EOF
}

/// Convert token to string for error messages.
pub fn to_string(tok: Token) -> String {
  case tok {
    KeywordBlueprints -> "Blueprints"
    KeywordExpectations -> "Expectations"
    KeywordFor -> "for"
    KeywordExtends -> "extends"
    KeywordRequires -> "Requires"
    KeywordProvides -> "Provides"
    KeywordIn -> "in"
    KeywordX -> "x"
    KeywordString -> "String"
    KeywordInteger -> "Integer"
    KeywordFloat -> "Float"
    KeywordBoolean -> "Boolean"
    KeywordList -> "List"
    KeywordDict -> "Dict"
    KeywordOptional -> "Optional"
    KeywordDefaulted -> "Defaulted"
    LiteralString(s) -> "\"" <> s <> "\""
    LiteralInteger(_) -> "integer"
    LiteralFloat(_) -> "float"
    LiteralTrue -> "true"
    LiteralFalse -> "false"
    SymbolLeftBrace -> "{"
    SymbolRightBrace -> "}"
    SymbolLeftParen -> "("
    SymbolRightParen -> ")"
    SymbolLeftBracket -> "["
    SymbolRightBracket -> "]"
    SymbolColon -> ":"
    SymbolComma -> ","
    SymbolStar -> "*"
    SymbolPlus -> "+"
    SymbolPipe -> "|"
    SymbolEquals -> "="
    SymbolDotDot -> ".."
    WhitespaceNewline -> "newline"
    WhitespaceIndent(_) -> "indent"
    CommentLine(_) -> "comment"
    CommentSection(_) -> "section comment"
    Identifier(name) -> name
    EOF -> "end of file"
  }
}
