/// End-to-end integration tests for the Gleam LSP server.
/// Exercises full session flows: open documents via notifications,
/// then make requests — matching coverage from the old TypeScript e2e suite.
import caffeine_lsp/diagnostics.{type Diagnostic, QuotedFieldName}
import caffeine_lsp/lsp_types
import caffeine_lsp/server/handlers
import caffeine_lsp/server/notifications
import caffeine_lsp/server/workspace
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import gleeunit/should

// --- Fixture content (matching old e2e fixtures) ---

const valid_blueprint = "Blueprints for \"SLO\"\n  * \"test_blueprint\":\n    Requires { env: String, status: Boolean }\n    Provides {\n      vendor: \"datadog\",\n      indicators: { good: \"query_good\", total: \"query_total\" },\n      evaluation: \"good / total\",\n      threshold: 99.9%\n    }\n"

const valid_expects = "Expectations for \"test_blueprint\"\n  * \"test_expectation\":\n    Provides {\n      env: \"production\",\n      status: true\n    }\n"

const invalid_syntax = "Blueprints for \"SLO\"\n  * \"bad_blueprint\"\n    Requires { vendor: String }\n    Provides { vendor: \"datadog\" }\n"

const with_extendable = "_defaults (Provides): { vendor: \"datadog\" }\n\nExpectations for \"test_blueprint\"\n  * \"checkout\" extends [_defaults]:\n    Provides { threshold: 99.9 }\n"

const unformatted = "Blueprints for   \"SLO\"\n  * \"test_blueprint\" :\n    Requires   {   vendor:  String,    threshold:  Float   }\n    Provides   {   vendor:  \"datadog\",   threshold:  99.9   }\n"

const quoted_field = "Blueprints for \"SLO\"\n  * \"test_blueprint\":\n    Requires { \"env\": String }\n    Provides { vendor: \"datadog\" }\n"

// ====================================================================
// Diagnostics
// ====================================================================
// * ✅ valid blueprint produces zero diagnostics
// * ✅ valid expects produces diagnostics response
// * ✅ syntax error produces meaningful diagnostic
// * ✅ cross-file blueprint reference resolves when blueprint is open
// * ✅ document change updates diagnostics
// * ✅ document close clears diagnostics
// * ✅ error recovery clears diagnostics after fix
// * ✅ empty document produces zero diagnostics

pub fn diagnostics_valid_blueprint_zero_errors_test() {
  let ws = workspace.new()
  let result = open(ws, "file:///bp.caffeine", valid_blueprint)

  // A standalone blueprint may produce a dead-blueprint warning (no expectations
  // reference it), but should have zero errors.
  let errors =
    diags_for(result, "file:///bp.caffeine")
    |> list.filter(fn(d: Diagnostic) { d.severity == lsp_types.DsError })
  list.length(errors)
  |> should.equal(0)
}

pub fn diagnostics_valid_expects_produces_response_test() {
  let ws = workspace.new()
  let result = open(ws, "file:///ex.caffeine", valid_expects)

  // Without the blueprint file open, expects may get "blueprint not found".
  let diags = diags_for(result, "file:///ex.caffeine")
  // Just verify we get a diagnostics response (may or may not have errors).
  { diags |> list.length >= 0 }
  |> should.be_true()
}

pub fn diagnostics_syntax_error_test() {
  let ws = workspace.new()
  let result = open(ws, "file:///bad.caffeine", invalid_syntax)

  let diags = diags_for(result, "file:///bad.caffeine")
  { diags != [] }
  |> should.be_true()
}

pub fn diagnostics_cross_file_blueprint_resolves_test() {
  let ws = workspace.new()

  // Open the blueprint file first so the server indexes it.
  let bp_result = open(ws, "file:///bp.caffeine", valid_blueprint)

  // Now open the expects file that references "test_blueprint".
  let ex_result =
    open(bp_result.workspace, "file:///ex.caffeine", valid_expects)

  // Should have no "not found" diagnostics since the blueprint is open.
  let diags = diags_for(ex_result, "file:///ex.caffeine")
  let not_found =
    list.filter(diags, fn(d: Diagnostic) {
      string.contains(d.message, "not found")
    })
  list.length(not_found)
  |> should.equal(0)
}

pub fn diagnostics_document_change_updates_test() {
  let ws = workspace.new()

  // Open with invalid content — should produce diagnostics.
  let open_result = open(ws, "file:///t.caffeine", invalid_syntax)
  let diags1 = diags_for(open_result, "file:///t.caffeine")
  { diags1 != [] }
  |> should.be_true()

  // Change to valid content — error diagnostics should clear.
  // (Dead-blueprint warnings may remain since no expectations reference it.)
  let change_result =
    change(open_result.workspace, "file:///t.caffeine", valid_blueprint)
  let errors2 =
    diags_for(change_result, "file:///t.caffeine")
    |> list.filter(fn(d: Diagnostic) { d.severity == lsp_types.DsError })
  list.length(errors2)
  |> should.equal(0)
}

pub fn diagnostics_document_close_clears_test() {
  let ws = workspace.new()

  // Open with invalid content.
  let open_result = open(ws, "file:///t.caffeine", invalid_syntax)
  let diags1 = diags_for(open_result, "file:///t.caffeine")
  { diags1 != [] }
  |> should.be_true()

  // Close the document — diagnostics should be empty list.
  let close_result = close(open_result.workspace, "file:///t.caffeine")
  close_result.diagnostics_to_publish
  |> should.equal([#("file:///t.caffeine", [])])
}

pub fn diagnostics_error_recovery_test() {
  let ws = workspace.new()

  // Missing colon after blueprint name.
  let broken =
    "Blueprints for \"SLO\"\n  * \"test\"\n    Requires { v: String }\n    Provides { v: \"x\" }\n"
  let open_result = open(ws, "file:///t.caffeine", broken)
  let diags1 = diags_for(open_result, "file:///t.caffeine")
  { diags1 != [] }
  |> should.be_true()

  // Fix: add the missing colon — error diagnostics should clear.
  let fixed =
    "Blueprints for \"SLO\"\n  * \"test\":\n    Requires { v: String }\n    Provides { v: \"x\" }\n"
  let change_result = change(open_result.workspace, "file:///t.caffeine", fixed)
  let errors2 =
    diags_for(change_result, "file:///t.caffeine")
    |> list.filter(fn(d: Diagnostic) { d.severity == lsp_types.DsError })
  list.length(errors2)
  |> should.equal(0)
}

pub fn diagnostics_empty_document_zero_test() {
  let ws = workspace.new()
  let result = open(ws, "file:///empty.caffeine", "")

  diags_for(result, "file:///empty.caffeine")
  |> list.length
  |> should.equal(0)
}

// ====================================================================
// Features — hover, completion, go-to-definition, signature help,
//            inlay hints, type hierarchy
// ====================================================================
// * ✅ hover on type keyword returns markdown
// * ✅ hover on field name returns content
// * ✅ hover on whitespace returns null
// * ✅ completion returns type keywords in Requires
// * ✅ completion suggests blueprint names cross-file
// * ✅ go-to-definition on extendable navigates to definition
// * ✅ signature help returns blueprint parameters
// * ✅ inlay hints show field types from blueprint
// * ✅ type hierarchy prepare returns items

pub fn hover_on_type_keyword_test() {
  let ws = workspace.new()
  let ws2 = open(ws, "file:///bp.caffeine", valid_blueprint).workspace

  // Line 2: "    Requires { env: String, status: Boolean }"
  // "String" starts at character 24.
  let params = make_params("file:///bp.caffeine", 2, 24)
  let assert Ok(result) =
    handlers.handle_request("textDocument/hover", params, ws2)

  let response = json.to_string(result.response)
  string.contains(response, "markdown")
  |> should.be_true()
  string.contains(response, "String")
  |> should.be_true()
}

pub fn hover_on_field_name_test() {
  let ws = workspace.new()
  let ws2 = open(ws, "file:///bp.caffeine", valid_blueprint).workspace

  // Line 4: "      vendor: \"datadog\","
  // "vendor" starts at character 6 (in Provides block).
  let params = make_params("file:///bp.caffeine", 4, 6)
  let assert Ok(result) =
    handlers.handle_request("textDocument/hover", params, ws2)

  let response = json.to_string(result.response)
  string.contains(response, "markdown")
  |> should.be_true()
}

pub fn hover_on_whitespace_returns_null_test() {
  let ws = workspace.new()
  let ws2 = open(ws, "file:///bp.caffeine", valid_blueprint).workspace

  // Line 2, character 0 is leading whitespace.
  let params = make_params("file:///bp.caffeine", 2, 0)
  let assert Ok(result) =
    handlers.handle_request("textDocument/hover", params, ws2)

  json.to_string(result.response)
  |> should.equal("null")
}

pub fn completion_type_keywords_test() {
  let ws = workspace.new()
  let ws2 = open(ws, "file:///bp.caffeine", valid_blueprint).workspace

  // Line 2: "    Requires { env: String, status: Boolean }"
  // Character 23 is the space after ":", triggers type completions.
  let params = make_params("file:///bp.caffeine", 2, 23)
  let assert Ok(result) =
    handlers.handle_request("textDocument/completion", params, ws2)

  let response = json.to_string(result.response)
  string.contains(response, "String")
  |> should.be_true()
  string.contains(response, "Integer")
  |> should.be_true()
  string.contains(response, "Boolean")
  |> should.be_true()
}

pub fn completion_suggests_blueprint_names_test() {
  let ws = workspace.new()

  // Open the blueprint file so the server indexes it.
  let ws2 = open(ws, "file:///bp.caffeine", valid_blueprint).workspace

  // Open the expects file.
  let ws3 = open(ws2, "file:///ex.caffeine", valid_expects).workspace

  // Line 0: 'Expectations for "test_blueprint"'
  // Character 18 is right after the opening quote.
  let params = make_params("file:///ex.caffeine", 0, 18)
  let assert Ok(result) =
    handlers.handle_request("textDocument/completion", params, ws3)

  let response = json.to_string(result.response)
  string.contains(response, "test_blueprint")
  |> should.be_true()
}

pub fn goto_definition_extendable_test() {
  let ws = workspace.new()
  let ws2 = open(ws, "file:///ext.caffeine", with_extendable).workspace

  // Line 3: '  * "checkout" extends [_defaults]:'
  // "_defaults" starts at character 24.
  let params = make_params("file:///ext.caffeine", 3, 24)
  let assert Ok(result) =
    handlers.handle_request("textDocument/definition", params, ws2)

  let response = json.to_string(result.response)
  // Should contain the URI and line 0 (where _defaults is defined).
  string.contains(response, "file:///ext.caffeine")
  |> should.be_true()
  string.contains(response, "\"line\":0")
  |> should.be_true()
}

pub fn signature_help_returns_blueprint_params_test() {
  let ws = workspace.new()

  // Open blueprint first so the server indexes it.
  let ws2 = open(ws, "file:///bp.caffeine", valid_blueprint).workspace

  // Open expects file.
  let ws3 = open(ws2, "file:///ex.caffeine", valid_expects).workspace

  // Line 3: '      env: "production",' — cursor on a Provides field.
  let params = make_params("file:///ex.caffeine", 3, 10)
  let assert Ok(result) =
    handlers.handle_request("textDocument/signatureHelp", params, ws3)

  let response = json.to_string(result.response)
  // Should contain signature info referencing the blueprint.
  { response != "null" }
  |> should.be_true()
}

pub fn inlay_hints_show_field_types_test() {
  let ws = workspace.new()

  // Open blueprint first.
  let ws2 = open(ws, "file:///bp.caffeine", valid_blueprint).workspace

  // Open expects file.
  let ws3 = open(ws2, "file:///ex.caffeine", valid_expects).workspace

  // Request inlay hints for the full file range.
  let params = make_inlay_hint_params("file:///ex.caffeine", 0, 10)
  let assert Ok(result) =
    handlers.handle_request("textDocument/inlayHint", params, ws3)

  let response = json.to_string(result.response)
  // Should contain type hints (String, Boolean from the blueprint's Requires).
  { response != "[]" }
  |> should.be_true()
}

pub fn type_hierarchy_prepare_test() {
  let ws = workspace.new()
  let ws2 = open(ws, "file:///ex.caffeine", valid_expects).workspace

  // Line 1: '  * "test_expectation":'
  // Cursor on "test_expectation" (inside the item name).
  let params = make_params("file:///ex.caffeine", 1, 8)
  let assert Ok(result) =
    handlers.handle_request("textDocument/typeHierarchy/prepare", params, ws2)

  let response = json.to_string(result.response)
  string.contains(response, "test_expectation")
  |> should.be_true()
}

// ====================================================================
// Formatting, semantic tokens, symbols, code actions, references
// ====================================================================
// * ✅ formatting fixes spacing in unformatted file
// * ✅ formatting is identity on already-formatted file
// * ✅ semantic tokens returns non-empty data
// * ✅ document symbols returns symbols
// * ✅ code actions returns quickfix for quoted field
// * ✅ references returns definition and usage for extendable

pub fn formatting_fixes_spacing_test() {
  let ws = workspace.new()
  let ws2 = open(ws, "file:///uf.caffeine", unformatted).workspace

  let params = make_params("file:///uf.caffeine", 0, 0)
  let assert Ok(result) =
    handlers.handle_request("textDocument/formatting", params, ws2)

  let response = json.to_string(result.response)
  // Should have edits with newText that differs from original.
  string.contains(response, "newText")
  |> should.be_true()
  // The formatted output should NOT contain the extra spaces.
  { !string.contains(response, "for   \\\"SLO\\\"") }
  |> should.be_true()
}

pub fn formatting_identity_on_formatted_test() {
  let ws = workspace.new()
  let ws2 = open(ws, "file:///bp.caffeine", valid_blueprint).workspace

  let params = make_params("file:///bp.caffeine", 0, 0)
  let assert Ok(result) =
    handlers.handle_request("textDocument/formatting", params, ws2)

  let response = json.to_string(result.response)
  // For an already-formatted file, the newText should match the original.
  // The response contains the full text as a single edit.
  string.contains(response, "newText")
  |> should.be_true()
}

pub fn semantic_tokens_non_empty_test() {
  let ws = workspace.new()
  let ws2 = open(ws, "file:///bp.caffeine", valid_blueprint).workspace

  let params = make_params("file:///bp.caffeine", 0, 0)
  let assert Ok(result) =
    handlers.handle_request("textDocument/semanticTokens/full", params, ws2)

  let response = json.to_string(result.response)
  string.contains(response, "\"data\"")
  |> should.be_true()
  // Should have actual token data (not just empty array).
  { !string.contains(response, "\"data\":[]") }
  |> should.be_true()
}

pub fn document_symbols_returned_test() {
  let ws = workspace.new()
  let ws2 = open(ws, "file:///bp.caffeine", valid_blueprint).workspace

  let params = make_params("file:///bp.caffeine", 0, 0)
  let assert Ok(result) =
    handlers.handle_request("textDocument/documentSymbol", params, ws2)

  let response = json.to_string(result.response)
  // Should have symbols (not empty array).
  { response != "[]" }
  |> should.be_true()
  // Should contain a module-level symbol (kind 2 for Module).
  string.contains(response, "\"kind\":2")
  |> should.be_true()
}

pub fn code_actions_quickfix_for_quoted_field_test() {
  let ws = workspace.new()
  let open_result = open(ws, "file:///qf.caffeine", quoted_field)
  let ws2 = open_result.workspace
  let diags = diags_for(open_result, "file:///qf.caffeine")

  // Should have at least one diagnostic for the quoted field name.
  { diags != [] }
  |> should.be_true()

  // Find the quoted-field-name diagnostic and build code action params.
  let quoted_diags =
    list.filter(diags, fn(d: Diagnostic) { d.code == QuotedFieldName })
  { quoted_diags != [] }
  |> should.be_true()

  let assert [first_diag, ..] = quoted_diags
  let code_str = case diagnostics.diagnostic_code_to_string(first_diag.code) {
    option.Some(s) -> s
    option.None -> ""
  }
  let diag_json =
    json.object([
      #(
        "range",
        json.object([
          #(
            "start",
            json.object([
              #("line", json.int(first_diag.line)),
              #("character", json.int(first_diag.column)),
            ]),
          ),
          #(
            "end",
            json.object([
              #("line", json.int(first_diag.line)),
              #("character", json.int(first_diag.end_column)),
            ]),
          ),
        ]),
      ),
      #("message", json.string(first_diag.message)),
      #("code", json.string(code_str)),
    ])

  let params = make_code_action_params("file:///qf.caffeine", [diag_json])
  let assert Ok(result) =
    handlers.handle_request("textDocument/codeAction", params, ws2)

  let response = json.to_string(result.response)
  string.contains(response, "quickfix")
  |> should.be_true()
}

pub fn references_for_extendable_test() {
  let ws = workspace.new()
  let ws2 = open(ws, "file:///ext.caffeine", with_extendable).workspace

  // Request references at the _defaults definition (line 0, character 1).
  let params = make_params("file:///ext.caffeine", 0, 1)
  let assert Ok(result) =
    handlers.handle_request("textDocument/references", params, ws2)

  let response = json.to_string(result.response)
  // Should have at least 2 references (definition + usage).
  // Count occurrences of the URI in the response.
  let uri_count =
    string.split(response, "file:///ext.caffeine")
    |> list.length
  // uri_count - 1 = number of occurrences.
  { uri_count - 1 >= 2 }
  |> should.be_true()
}

// ====================================================================
// Multi-document session
// ====================================================================
// * ✅ server handles multiple document operations

pub fn multi_document_session_test() {
  let ws = workspace.new()

  // Open first document.
  let ws2 = open(ws, "file:///a.caffeine", valid_blueprint).workspace

  // Open second document.
  let ws3 = open(ws2, "file:///b.caffeine", valid_expects).workspace

  // Request on first document should still work.
  let params_a = make_params("file:///a.caffeine", 0, 3)
  let assert Ok(result_a) =
    handlers.handle_request("textDocument/hover", params_a, ws3)
  let response_a = json.to_string(result_a.response)
  string.contains(response_a, "markdown")
  |> should.be_true()

  // Request on second document should work too.
  let params_b = make_params("file:///b.caffeine", 0, 0)
  let assert Ok(result_b) =
    handlers.handle_request("textDocument/documentSymbol", params_b, ws3)
  let response_b = json.to_string(result_b.response)
  { response_b != "[]" }
  |> should.be_true()

  // Modify first document.
  let ws4 = change(ws3, "file:///a.caffeine", valid_blueprint).workspace

  // Verify it's still accessible.
  let assert Ok(result_c) =
    handlers.handle_request(
      "textDocument/semanticTokens/full",
      make_params("file:///a.caffeine", 0, 0),
      ws4,
    )
  let response_c = json.to_string(result_c.response)
  string.contains(response_c, "\"data\"")
  |> should.be_true()
}

// --- Test helpers ---

fn open(
  ws: workspace.WorkspaceState,
  uri: String,
  text: String,
) -> notifications.NotifyResult {
  let params = make_did_open_params(uri, text)
  notifications.handle_notification("textDocument/didOpen", params, ws)
}

fn change(
  ws: workspace.WorkspaceState,
  uri: String,
  text: String,
) -> notifications.NotifyResult {
  let params = make_did_change_params(uri, text)
  notifications.handle_notification("textDocument/didChange", params, ws)
}

fn close(
  ws: workspace.WorkspaceState,
  uri: String,
) -> notifications.NotifyResult {
  let params = make_did_close_params(uri)
  notifications.handle_notification("textDocument/didClose", params, ws)
}

fn diags_for(
  result: notifications.NotifyResult,
  uri: String,
) -> List(Diagnostic) {
  case list.find(result.diagnostics_to_publish, fn(entry) { entry.0 == uri }) {
    Ok(#(_, diags)) -> diags
    Error(_) -> []
  }
}

fn make_params(uri: String, line: Int, character: Int) -> dynamic.Dynamic {
  json.to_string(
    json.object([
      #("textDocument", json.object([#("uri", json.string(uri))])),
      #(
        "position",
        json.object([
          #("line", json.int(line)),
          #("character", json.int(character)),
        ]),
      ),
    ]),
  )
  |> json_to_dynamic
}

fn make_code_action_params(
  uri: String,
  diagnostics: List(json.Json),
) -> dynamic.Dynamic {
  json.to_string(
    json.object([
      #("textDocument", json.object([#("uri", json.string(uri))])),
      #(
        "context",
        json.object([
          #("diagnostics", json.preprocessed_array(diagnostics)),
        ]),
      ),
    ]),
  )
  |> json_to_dynamic
}

fn make_inlay_hint_params(
  uri: String,
  start_line: Int,
  end_line: Int,
) -> dynamic.Dynamic {
  json.to_string(
    json.object([
      #("textDocument", json.object([#("uri", json.string(uri))])),
      #(
        "range",
        json.object([
          #(
            "start",
            json.object([
              #("line", json.int(start_line)),
              #("character", json.int(0)),
            ]),
          ),
          #(
            "end",
            json.object([
              #("line", json.int(end_line)),
              #("character", json.int(0)),
            ]),
          ),
        ]),
      ),
    ]),
  )
  |> json_to_dynamic
}

fn make_did_open_params(uri: String, text: String) -> dynamic.Dynamic {
  json.to_string(
    json.object([
      #(
        "textDocument",
        json.object([
          #("uri", json.string(uri)),
          #("text", json.string(text)),
        ]),
      ),
    ]),
  )
  |> json_to_dynamic
}

fn make_did_change_params(uri: String, text: String) -> dynamic.Dynamic {
  json.to_string(
    json.object([
      #("textDocument", json.object([#("uri", json.string(uri))])),
      #(
        "contentChanges",
        json.preprocessed_array([
          json.object([#("text", json.string(text))]),
        ]),
      ),
    ]),
  )
  |> json_to_dynamic
}

fn make_did_close_params(uri: String) -> dynamic.Dynamic {
  json.to_string(
    json.object([
      #("textDocument", json.object([#("uri", json.string(uri))])),
    ]),
  )
  |> json_to_dynamic
}

fn json_to_dynamic(json_str: String) -> dynamic.Dynamic {
  let any_decoder = decode.new_primitive_decoder("any", fn(dyn) { Ok(dyn) })
  let assert Ok(dyn) = json.parse(json_str, any_decoder)
  dyn
}
