/// LSP response encoders — convert Gleam feature module results to JSON.
import caffeine_lsp/code_actions.{type CodeAction, type TextEdit}
import caffeine_lsp/completion.{type CompletionItem}
import caffeine_lsp/diagnostics.{type Diagnostic}
import caffeine_lsp/document_symbols.{type DocumentSymbol}
import caffeine_lsp/folding_range.{type FoldingRange}
import caffeine_lsp/inlay_hints.{type InlayHint}
import caffeine_lsp/lsp_types
import caffeine_lsp/selection_range.{type SelectionRange, HasParent, NoParent}
import caffeine_lsp/signature_help.{type SignatureHelp}
import caffeine_lsp/type_hierarchy.{
  type TypeHierarchyItem, type TypeHierarchyKind, BlueprintKind, ExpectationKind,
}
import caffeine_lsp/workspace_symbols.{type WorkspaceSymbol}
import gleam/json
import gleam/list
import gleam/option

// --- Primitives ---

/// Encode an LSP Range.
pub fn range(
  start_line: Int,
  start_char: Int,
  end_line: Int,
  end_char: Int,
) -> json.Json {
  json.object([
    #(
      "start",
      json.object([
        #("line", json.int(start_line)),
        #("character", json.int(start_char)),
      ]),
    ),
    #(
      "end",
      json.object([
        #("line", json.int(end_line)),
        #("character", json.int(end_char)),
      ]),
    ),
  ])
}

/// Encode a Location.
pub fn location(uri: String, r: json.Json) -> json.Json {
  json.object([#("uri", json.string(uri)), #("range", r)])
}

// --- Diagnostics ---

/// Encode a Diagnostic to LSP JSON.
pub fn encode_diagnostic(d: Diagnostic) -> json.Json {
  let base = [
    #("range", range(d.line, d.column, d.line, d.end_column)),
    #("severity", json.int(lsp_types.diagnostic_severity_to_int(d.severity))),
    #("source", json.string("caffeine")),
    #("message", json.string(d.message)),
  ]
  let fields = case diagnostics.diagnostic_code_to_string(d.code) {
    option.Some(code_str) ->
      list.append(base, [#("code", json.string(code_str))])
    option.None -> base
  }
  json.object(fields)
}

/// Encode a list of diagnostics as a publishDiagnostics params object.
pub fn encode_publish_diagnostics(
  uri: String,
  diags: List(Diagnostic),
) -> json.Json {
  json.object([
    #("uri", json.string(uri)),
    #(
      "diagnostics",
      json.preprocessed_array(list.map(diags, encode_diagnostic)),
    ),
  ])
}

// --- Hover ---

/// Encode hover result (markdown content).
pub fn encode_hover(content: String) -> json.Json {
  json.object([
    #(
      "contents",
      json.object([
        #("kind", json.string("markdown")),
        #("value", json.string(content)),
      ]),
    ),
  ])
}

// --- Completion ---

/// Encode a CompletionItem to LSP JSON.
pub fn encode_completion_item(item: CompletionItem) -> json.Json {
  let base = [
    #("label", json.string(item.label)),
    #("kind", json.int(item.kind)),
    #("detail", json.string(item.detail)),
  ]
  let with_insert_text = case item.insert_text {
    option.Some(text) -> list.append(base, [#("insertText", json.string(text))])
    option.None -> base
  }
  let with_format = case item.insert_text_format {
    option.Some(fmt) ->
      list.append(with_insert_text, [#("insertTextFormat", json.int(fmt))])
    option.None -> with_insert_text
  }
  json.object(with_format)
}

/// Encode a list of completion items.
pub fn encode_completion_items(items: List(CompletionItem)) -> json.Json {
  json.preprocessed_array(list.map(items, encode_completion_item))
}

// --- Document symbols ---

/// Encode a DocumentSymbol recursively.
pub fn encode_document_symbol(sym: DocumentSymbol) -> json.Json {
  let r = range(sym.line, sym.col, sym.line, sym.col + sym.name_len)
  json.object([
    #("name", json.string(sym.name)),
    #("detail", json.string(sym.detail)),
    #("kind", json.int(sym.kind)),
    #("range", r),
    #("selectionRange", r),
    #(
      "children",
      json.preprocessed_array(list.map(sym.children, encode_document_symbol)),
    ),
  ])
}

/// Encode a list of document symbols.
pub fn encode_document_symbols(syms: List(DocumentSymbol)) -> json.Json {
  json.preprocessed_array(list.map(syms, encode_document_symbol))
}

// --- Semantic tokens ---

/// Encode semantic tokens response.
pub fn encode_semantic_tokens(data: List(Int)) -> json.Json {
  json.object([
    #("data", json.preprocessed_array(list.map(data, json.int))),
  ])
}

// --- Formatting ---

/// Encode a full-document text edit.
pub fn encode_formatting(formatted: String, line_count: Int) -> json.Json {
  json.preprocessed_array([
    json.object([
      #("range", range(0, 0, line_count, 0)),
      #("newText", json.string(formatted)),
    ]),
  ])
}

// --- Code actions ---

/// Encode a CodeAction to LSP JSON.
pub fn encode_code_action(action: CodeAction) -> json.Json {
  let diag = action.diagnostic
  json.object([
    #("title", json.string(action.title)),
    #("kind", json.string(action.kind)),
    #("isPreferred", json.bool(action.is_preferred)),
    #(
      "diagnostics",
      json.preprocessed_array([
        json.object([
          #("message", json.string(diag.message)),
          #("source", json.string("caffeine")),
          #(
            "range",
            range(diag.line, diag.character, diag.end_line, diag.end_character),
          ),
        ]),
      ]),
    ),
    #(
      "edit",
      json.object([
        #(
          "changes",
          json.object([
            #(
              action.uri,
              json.preprocessed_array(list.map(action.edits, encode_text_edit)),
            ),
          ]),
        ),
      ]),
    ),
  ])
}

fn encode_text_edit(edit: TextEdit) -> json.Json {
  json.object([
    #(
      "range",
      range(
        edit.start_line,
        edit.start_character,
        edit.end_line,
        edit.end_character,
      ),
    ),
    #("newText", json.string(edit.new_text)),
  ])
}

/// Encode a list of code actions.
pub fn encode_code_actions(actions: List(CodeAction)) -> json.Json {
  json.preprocessed_array(list.map(actions, encode_code_action))
}

// --- Rename ---

/// Encode prepare rename result.
pub fn encode_prepare_rename(
  line: Int,
  col: Int,
  name_len: Int,
  placeholder: String,
) -> json.Json {
  json.object([
    #("range", range(line, col, line, col + name_len)),
    #("placeholder", json.string(placeholder)),
  ])
}

/// Encode rename edits as a WorkspaceEdit.
pub fn encode_rename_edits(
  uri: String,
  edits: List(#(Int, Int, Int)),
  new_name: String,
) -> json.Json {
  json.object([
    #(
      "changes",
      json.object([
        #(
          uri,
          json.preprocessed_array(
            list.map(edits, fn(e) {
              let #(line, col, len) = e
              json.object([
                #("range", range(line, col, line, col + len)),
                #("newText", json.string(new_name)),
              ])
            }),
          ),
        ),
      ]),
    ),
  ])
}

// --- Highlights ---

/// Encode document highlights.
pub fn encode_highlights(highlights: List(#(Int, Int, Int))) -> json.Json {
  json.preprocessed_array(
    list.map(highlights, fn(h) {
      let #(line, col, len) = h
      json.object([
        #("range", range(line, col, line, col + len)),
        #("kind", json.int(1)),
      ])
    }),
  )
}

// --- Folding ranges ---

/// Encode folding ranges.
pub fn encode_folding_ranges(ranges: List(FoldingRange)) -> json.Json {
  json.preprocessed_array(
    list.map(ranges, fn(r) {
      json.object([
        #("startLine", json.int(r.start_line)),
        #("endLine", json.int(r.end_line)),
        #("kind", json.string("region")),
      ])
    }),
  )
}

// --- Selection ranges ---

/// Encode a selection range recursively.
pub fn encode_selection_range(sr: SelectionRange) -> json.Json {
  let r = range(sr.start_line, sr.start_col, sr.end_line, sr.end_col)
  case sr.parent {
    HasParent(parent) ->
      json.object([
        #("range", r),
        #("parent", encode_selection_range(parent)),
      ])
    NoParent -> json.object([#("range", r)])
  }
}

// --- Linked editing ranges ---

/// Encode linked editing ranges.
pub fn encode_linked_editing_ranges(ranges: List(#(Int, Int, Int))) -> json.Json {
  json.object([
    #(
      "ranges",
      json.preprocessed_array(
        list.map(ranges, fn(r) {
          let #(line, col, len) = r
          range(line, col, line, col + len)
        }),
      ),
    ),
  ])
}

// --- Signature help ---

/// Encode signature help result.
pub fn encode_signature_help(sig: SignatureHelp) -> json.Json {
  json.object([
    #(
      "signatures",
      json.preprocessed_array([
        json.object([
          #("label", json.string(sig.label)),
          #(
            "parameters",
            json.preprocessed_array(
              list.map(sig.parameters, fn(p) {
                json.object([
                  #("label", json.string(p.label)),
                  #("documentation", json.string(p.documentation)),
                ])
              }),
            ),
          ),
          #("activeParameter", json.int(sig.active_parameter)),
        ]),
      ]),
    ),
    #("activeSignature", json.int(0)),
    #("activeParameter", json.int(sig.active_parameter)),
  ])
}

// --- Inlay hints ---

/// Encode inlay hints.
pub fn encode_inlay_hints(hints: List(InlayHint)) -> json.Json {
  json.preprocessed_array(
    list.map(hints, fn(h) {
      json.object([
        #(
          "position",
          json.object([
            #("line", json.int(h.line)),
            #("character", json.int(h.column)),
          ]),
        ),
        #("label", json.string(h.label)),
        #("kind", json.int(h.kind)),
        #("paddingLeft", json.bool(h.padding_left)),
      ])
    }),
  )
}

// --- Type hierarchy ---

/// Encode type hierarchy kind to LSP SymbolKind.
fn type_hierarchy_kind_to_int(kind: TypeHierarchyKind) -> Int {
  case kind {
    BlueprintKind -> 5
    ExpectationKind -> 13
  }
}

/// Encode a type hierarchy item with data for supertypes/subtypes roundtrip.
pub fn encode_type_hierarchy_item(
  item: TypeHierarchyItem,
  uri: String,
) -> json.Json {
  let r = range(item.line, item.col, item.line, item.col + item.name_len)
  let kind_str = case item.kind {
    BlueprintKind -> "blueprint"
    ExpectationKind -> "expectation"
  }
  json.object([
    #("name", json.string(item.name)),
    #("kind", json.int(type_hierarchy_kind_to_int(item.kind))),
    #("uri", json.string(uri)),
    #("range", r),
    #("selectionRange", r),
    #(
      "data",
      json.object([
        #("kind", json.string(kind_str)),
        #("blueprint", json.string(item.blueprint)),
      ]),
    ),
  ])
}

/// Encode type hierarchy items.
pub fn encode_type_hierarchy_items(
  items: List(TypeHierarchyItem),
  uri: String,
) -> json.Json {
  json.preprocessed_array(
    list.map(items, fn(item) { encode_type_hierarchy_item(item, uri) }),
  )
}

// --- Workspace symbols ---

/// Encode workspace symbols for workspace/symbol response.
pub fn encode_workspace_symbols(
  symbols: List(#(String, WorkspaceSymbol)),
) -> json.Json {
  json.preprocessed_array(
    list.map(symbols, fn(entry) {
      let #(uri, sym) = entry
      let r = range(sym.line, sym.col, sym.line, sym.col + sym.name_len)
      json.object([
        #("name", json.string(sym.name)),
        #("kind", json.int(sym.kind)),
        #("location", location(uri, r)),
      ])
    }),
  )
}

// --- Definition ---

/// Encode a definition location.
pub fn encode_definition(
  uri: String,
  line: Int,
  col: Int,
  name_len: Int,
) -> json.Json {
  json.object([
    #("uri", json.string(uri)),
    #("range", range(line, col, line, col + name_len)),
  ])
}

// --- References ---

/// Encode reference locations.
pub fn encode_references(uri: String, refs: List(#(Int, Int, Int))) -> json.Json {
  json.preprocessed_array(
    list.map(refs, fn(r) {
      let #(line, col, len) = r
      location(uri, range(line, col, line, col + len))
    }),
  )
}
