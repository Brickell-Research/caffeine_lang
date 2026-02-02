/// Typed enums for LSP protocol constants, replacing raw integer magic numbers.
/// LSP CompletionItemKind values.
pub type CompletionItemKind {
  CikKeyword
  CikClass
  CikVariable
  CikField
}

/// Converts a CompletionItemKind to its LSP protocol integer.
pub fn completion_item_kind_to_int(k: CompletionItemKind) -> Int {
  case k {
    CikKeyword -> 14
    CikClass -> 7
    CikVariable -> 6
    CikField -> 5
  }
}

/// LSP SymbolKind values.
pub type SymbolKind {
  SkModule
  SkClass
  SkProperty
  SkVariable
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
pub type DiagnosticSeverity {
  DsError
  DsWarning
}

/// Converts a DiagnosticSeverity to its LSP protocol integer.
pub fn diagnostic_severity_to_int(k: DiagnosticSeverity) -> Int {
  case k {
    DsError -> 1
    DsWarning -> 2
  }
}

/// LSP semantic token type indices matching the token_types legend.
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
