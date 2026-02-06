/// Typed enums for LSP protocol constants, replacing raw integer magic numbers.
/// See: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/
/// LSP CompletionItemKind values.
/// See: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#completionItemKind
pub type CompletionItemKind {
  /// LSP CompletionItemKind 14.
  CikKeyword
  /// LSP CompletionItemKind 7.
  CikClass
  /// LSP CompletionItemKind 6.
  CikVariable
  /// LSP CompletionItemKind 5.
  CikField
  /// LSP CompletionItemKind 9.
  CikModule
}

/// Converts a CompletionItemKind to its LSP protocol integer.
pub fn completion_item_kind_to_int(k: CompletionItemKind) -> Int {
  case k {
    CikKeyword -> 14
    CikClass -> 7
    CikVariable -> 6
    CikField -> 5
    CikModule -> 9
  }
}

/// LSP SymbolKind values.
/// See: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#symbolKind
pub type SymbolKind {
  /// LSP SymbolKind 2.
  SkModule
  /// LSP SymbolKind 5.
  SkClass
  /// LSP SymbolKind 7.
  SkProperty
  /// LSP SymbolKind 13.
  SkVariable
  /// LSP SymbolKind 26.
  SkTypeParameter
}

/// Converts a SymbolKind to its LSP protocol integer.
pub fn symbol_kind_to_int(k: SymbolKind) -> Int {
  case k {
    SkModule -> 2
    SkClass -> 5
    SkProperty -> 7
    SkVariable -> 13
    SkTypeParameter -> 26
  }
}

/// LSP DiagnosticSeverity values.
/// See: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#diagnosticSeverity
pub type DiagnosticSeverity {
  /// LSP DiagnosticSeverity 1.
  DsError
  /// LSP DiagnosticSeverity 2.
  DsWarning
}

/// Converts a DiagnosticSeverity to its LSP protocol integer.
pub fn diagnostic_severity_to_int(k: DiagnosticSeverity) -> Int {
  case k {
    DsError -> 1
    DsWarning -> 2
  }
}

/// LSP semantic token type indices matching the token_types legend
/// in `semantic_tokens.gleam`. These are not protocol constants — they
/// are positional indices into the legend array registered with the client.
pub type SemanticTokenType {
  SttKeyword
  SttType
  SttString
  SttNumber
  SttVariable
  SttComment
  SttOperator
  SttProperty
  SttFunction
  SttModifier
  SttEnumMember
}

/// Converts a SemanticTokenType to its string name in the legend.
@internal
pub fn semantic_token_type_to_string(k: SemanticTokenType) -> String {
  case k {
    SttKeyword -> "keyword"
    SttType -> "type"
    SttString -> "string"
    SttNumber -> "number"
    SttVariable -> "variable"
    SttComment -> "comment"
    SttOperator -> "operator"
    SttProperty -> "property"
    SttFunction -> "function"
    SttModifier -> "modifier"
    SttEnumMember -> "enumMember"
  }
}

/// Converts a SemanticTokenType to its index in the token_types legend.
pub fn semantic_token_type_to_int(k: SemanticTokenType) -> Int {
  case k {
    SttKeyword -> 0
    SttType -> 1
    SttString -> 2
    SttNumber -> 3
    SttVariable -> 4
    SttComment -> 5
    SttOperator -> 6
    SttProperty -> 7
    SttFunction -> 8
    SttModifier -> 9
    SttEnumMember -> 10
  }
}
