import caffeine_lsp/completion.{CompletionItem}
import caffeine_lsp/diagnostics.{Diagnostic, NoDiagnosticCode, QuotedFieldName}
import caffeine_lsp/document_symbols.{DocumentSymbol}
import caffeine_lsp/folding_range.{FoldingRange}
import caffeine_lsp/lsp_types.{DsError}
import caffeine_lsp/selection_range.{HasParent, NoParent, SelectionRange}
import caffeine_lsp/server/responses
import gleam/json
import gleam/option
import gleam/string
import gleeunit/should

// ==== encode_diagnostic ====
// * ✅ encodes diagnostic with code
// * ✅ encodes diagnostic without code

pub fn encode_diagnostic_with_code_test() {
  let d =
    Diagnostic(
      line: 1,
      column: 2,
      end_column: 10,
      severity: DsError,
      message: "test error",
      code: QuotedFieldName,
    )
  let result = json.to_string(responses.encode_diagnostic(d))
  result
  |> should.equal(
    json.to_string(
      json.object([
        #("range", responses.range(1, 2, 1, 10)),
        #("severity", json.int(1)),
        #("source", json.string("caffeine")),
        #("message", json.string("test error")),
        #("code", json.string("quoted-field-name")),
      ]),
    ),
  )
}

pub fn encode_diagnostic_no_code_test() {
  let d =
    Diagnostic(
      line: 0,
      column: 0,
      end_column: 5,
      severity: DsError,
      message: "parse error",
      code: NoDiagnosticCode,
    )
  let result = json.to_string(responses.encode_diagnostic(d))
  // Should not contain "code" field.
  string.contains(result, "\"code\"") |> should.be_false()
}

// ==== encode_hover ====
// * ✅ encodes hover markdown

pub fn encode_hover_test() {
  let result = json.to_string(responses.encode_hover("**bold**"))
  string.contains(result, "markdown") |> should.be_true()
  string.contains(result, "**bold**") |> should.be_true()
}

// ==== encode_completion_item ====
// * ✅ encodes basic completion
// * ✅ encodes with insert text

pub fn encode_completion_item_basic_test() {
  let item =
    CompletionItem(
      label: "test",
      kind: 14,
      detail: "keyword",
      insert_text: option.None,
      insert_text_format: option.None,
    )
  let result = json.to_string(responses.encode_completion_item(item))
  string.contains(result, "\"test\"") |> should.be_true()
  string.contains(result, "insertText") |> should.be_false()
}

pub fn encode_completion_item_with_insert_text_test() {
  let item =
    CompletionItem(
      label: "test",
      kind: 14,
      detail: "keyword",
      insert_text: option.Some("test: "),
      insert_text_format: option.Some(2),
    )
  let result = json.to_string(responses.encode_completion_item(item))
  string.contains(result, "insertText") |> should.be_true()
  string.contains(result, "insertTextFormat") |> should.be_true()
}

// ==== encode_document_symbol ====
// * ✅ encodes nested symbols

pub fn encode_document_symbol_test() {
  let sym =
    DocumentSymbol(
      name: "parent",
      detail: "block",
      kind: 2,
      line: 0,
      col: 0,
      name_len: 6,
      children: [
        DocumentSymbol(
          name: "child",
          detail: "item",
          kind: 5,
          line: 1,
          col: 2,
          name_len: 5,
          children: [],
        ),
      ],
    )
  let result = json.to_string(responses.encode_document_symbol(sym))
  string.contains(result, "\"parent\"") |> should.be_true()
  string.contains(result, "\"child\"") |> should.be_true()
}

// ==== encode_folding_ranges ====
// * ✅ encodes folding ranges

pub fn encode_folding_ranges_test() {
  let result =
    json.to_string(
      responses.encode_folding_ranges([FoldingRange(start_line: 0, end_line: 5)]),
    )
  string.contains(result, "\"startLine\":0") |> should.be_true()
  string.contains(result, "\"endLine\":5") |> should.be_true()
  string.contains(result, "\"region\"") |> should.be_true()
}

// ==== encode_selection_range ====
// * ✅ encodes with parent
// * ✅ encodes without parent

pub fn encode_selection_range_with_parent_test() {
  let parent =
    SelectionRange(
      start_line: 0,
      start_col: 0,
      end_line: 10,
      end_col: 0,
      parent: NoParent,
    )
  let sr =
    SelectionRange(
      start_line: 2,
      start_col: 4,
      end_line: 2,
      end_col: 20,
      parent: HasParent(parent),
    )
  let result = json.to_string(responses.encode_selection_range(sr))
  string.contains(result, "parent") |> should.be_true()
}

pub fn encode_selection_range_no_parent_test() {
  let sr =
    SelectionRange(
      start_line: 0,
      start_col: 0,
      end_line: 5,
      end_col: 0,
      parent: NoParent,
    )
  let result = json.to_string(responses.encode_selection_range(sr))
  string.contains(result, "\"parent\"") |> should.be_false()
}
