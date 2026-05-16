/// A token with source position information.
pub type PositionedToken {
  PositionedToken(token: Token, line: Int, column: Int)
}

/// A token produced by the tokenizer.
pub type Token {
  KeywordAssumes
  KeywordGuarantees
  KeywordOver
  KeywordWindow
  KeywordAs
  KeywordMeasured
  KeywordBy
  KeywordWith
  KeywordBelow
  KeywordHard
  KeywordSoft
  KeywordDependency
  KeywordOn
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
  KeywordType
  KeywordURL
  KeywordPercentage
  LiteralString(String)
  LiteralInteger(Int)
  LiteralFloat(Float)
  LiteralPercentage(Float)
  /// A duration literal like `10d`, `50ms`, `0.200s`. `unit` is the raw suffix
  /// as written (one of "ms", "s", "m", "h", "d"); kept as a string so the
  /// formatter can round-trip the source.
  LiteralDuration(amount: Float, unit: String)
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
  SymbolPipe
  SymbolEquals
  SymbolDotDot
  WhitespaceNewline
  WhitespaceIndent(Int)
  CommentLine(String)
  CommentSection(String)
  CommentDoc(String)
  Identifier(String)
  EOF
}

/// Convert token to string for error messages.
@internal
pub fn to_string(tok: Token) -> String {
  case tok {
    KeywordAssumes -> "Assumes"
    KeywordGuarantees -> "Guarantees"
    KeywordOver -> "over"
    KeywordWindow -> "window"
    KeywordAs -> "as"
    KeywordMeasured -> "measured"
    KeywordBy -> "by"
    KeywordWith -> "with"
    KeywordBelow -> "below"
    KeywordHard -> "hard"
    KeywordSoft -> "soft"
    KeywordDependency -> "dependency"
    KeywordOn -> "on"
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
    KeywordType -> "Type"
    KeywordURL -> "URL"
    KeywordPercentage -> "Percentage"
    LiteralString(s) -> "\"" <> s <> "\""
    LiteralInteger(_) -> "integer"
    LiteralFloat(_) -> "float"
    LiteralPercentage(_) -> "percentage"
    LiteralDuration(_, _) -> "duration"
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
    SymbolPipe -> "|"
    SymbolEquals -> "="
    SymbolDotDot -> ".."
    WhitespaceNewline -> "newline"
    WhitespaceIndent(_) -> "indent"
    CommentLine(_) -> "comment"
    CommentSection(_) -> "section comment"
    CommentDoc(_) -> "doc comment"
    Identifier(name) -> name
    EOF -> "end of file"
  }
}
