import caffeine_lsp/server/handlers
import caffeine_lsp/server/workspace
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

// ==== handle_request ====
// * ✅ routes known method
// * ✅ returns Error for unknown method
// * ✅ returns null when document not found

pub fn handle_request_routes_known_method_test() {
  let ws = workspace.new()
  let params = make_params("file:///test.caffeine", 0, 0)

  let assert Ok(result) =
    handlers.handle_request("textDocument/hover", params, ws)

  // No document open, so should get null.
  json.to_string(result.response)
  |> should.equal("null")
}

pub fn handle_request_unknown_method_test() {
  let ws = workspace.new()
  let params = make_params("file:///test.caffeine", 0, 0)

  handlers.handle_request("textDocument/unknown", params, ws)
  |> should.be_error()
}

pub fn handle_request_no_document_returns_null_test() {
  let ws = workspace.new()
  let params = make_params("file:///missing.caffeine", 0, 0)

  let assert Ok(result) =
    handlers.handle_request("textDocument/hover", params, ws)
  json.to_string(result.response)
  |> should.equal("null")
}

// ==== hover ====
// * ✅ returns null when no hover info
// * ✅ returns hover content for keyword

pub fn hover_no_info_test() {
  let ws = open_doc(workspace.new(), "file:///t.caffeine", "")
  let params = make_params("file:///t.caffeine", 0, 0)

  let assert Ok(result) =
    handlers.handle_request("textDocument/hover", params, ws)
  json.to_string(result.response)
  |> should.equal("null")
}

pub fn hover_returns_content_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let ws = open_doc(workspace.new(), "file:///t.caffeine", source)
  // Hover on "Blueprints" keyword at (0, 3).
  let params = make_params("file:///t.caffeine", 0, 3)

  let assert Ok(result) =
    handlers.handle_request("textDocument/hover", params, ws)
  let response_str = json.to_string(result.response)
  string.contains(response_str, "markdown")
  |> should.be_true()
}

// ==== document symbols ====
// * ✅ returns symbols for document

pub fn document_symbol_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let ws = open_doc(workspace.new(), "file:///t.caffeine", source)
  let params = make_params("file:///t.caffeine", 0, 0)

  let assert Ok(result) =
    handlers.handle_request("textDocument/documentSymbol", params, ws)
  let response_str = json.to_string(result.response)
  // Should contain symbol names from the parsed source.
  { response_str != "[]" }
  |> should.be_true()
}

// ==== semantic tokens ====
// * ✅ returns token data for source

pub fn semantic_tokens_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let ws = open_doc(workspace.new(), "file:///t.caffeine", source)
  let params = make_params("file:///t.caffeine", 0, 0)

  let assert Ok(result) =
    handlers.handle_request("textDocument/semanticTokens/full", params, ws)
  let response_str = json.to_string(result.response)
  // Should contain "data" key with token array.
  string.contains(response_str, "\"data\"")
  |> should.be_true()
}

// ==== folding ranges ====
// * ✅ returns folding ranges

pub fn folding_ranges_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let ws = open_doc(workspace.new(), "file:///t.caffeine", source)
  let params = make_params("file:///t.caffeine", 0, 0)

  let assert Ok(result) =
    handlers.handle_request("textDocument/foldingRange", params, ws)
  let response_str = json.to_string(result.response)
  string.contains(response_str, "startLine")
  |> should.be_true()
}

// ==== formatting ====
// * ✅ returns formatted text edit

pub fn formatting_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let ws = open_doc(workspace.new(), "file:///t.caffeine", source)
  let params = make_params("file:///t.caffeine", 0, 0)

  let assert Ok(result) =
    handlers.handle_request("textDocument/formatting", params, ws)
  let response_str = json.to_string(result.response)
  string.contains(response_str, "newText")
  |> should.be_true()
}

// ==== highlight ====
// * ✅ returns empty array when no highlights

pub fn highlight_empty_test() {
  let ws = open_doc(workspace.new(), "file:///t.caffeine", "")
  let params = make_params("file:///t.caffeine", 0, 0)

  let assert Ok(result) =
    handlers.handle_request("textDocument/documentHighlight", params, ws)
  json.to_string(result.response)
  |> should.equal("[]")
}

// ==== linked editing ====
// * ✅ returns null when no linked ranges

pub fn linked_editing_empty_test() {
  let ws = open_doc(workspace.new(), "file:///t.caffeine", "")
  let params = make_params("file:///t.caffeine", 0, 0)

  let assert Ok(result) =
    handlers.handle_request("textDocument/linkedEditingRange", params, ws)
  json.to_string(result.response)
  |> should.equal("null")
}

// ==== prepare rename ====
// * ✅ returns null when not on renameable symbol

pub fn prepare_rename_empty_test() {
  let ws = open_doc(workspace.new(), "file:///t.caffeine", "")
  let params = make_params("file:///t.caffeine", 0, 0)

  let assert Ok(result) =
    handlers.handle_request("textDocument/prepareRename", params, ws)
  json.to_string(result.response)
  |> should.equal("null")
}

// ==== rename ====
// * ✅ returns null when not on renameable symbol

pub fn rename_empty_test() {
  let ws = open_doc(workspace.new(), "file:///t.caffeine", "")
  let params = make_rename_params("file:///t.caffeine", 0, 0, "newName")

  let assert Ok(result) =
    handlers.handle_request("textDocument/rename", params, ws)
  json.to_string(result.response)
  |> should.equal("null")
}

// ==== code action ====
// * ✅ returns empty array when no diagnostics

pub fn code_action_empty_test() {
  let ws = workspace.new()
  let params = make_code_action_params("file:///t.caffeine", [])

  let assert Ok(result) =
    handlers.handle_request("textDocument/codeAction", params, ws)
  json.to_string(result.response)
  |> should.equal("[]")
}

// ==== type hierarchy prepare ====
// * ✅ returns null when not on type

pub fn type_hierarchy_prepare_empty_test() {
  let ws = open_doc(workspace.new(), "file:///t.caffeine", "")
  let params = make_params("file:///t.caffeine", 0, 0)

  let assert Ok(result) =
    handlers.handle_request("textDocument/typeHierarchy/prepare", params, ws)
  json.to_string(result.response)
  |> should.equal("null")
}

// ==== selection range ====
// * ✅ returns selection ranges for positions

pub fn selection_range_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let ws = open_doc(workspace.new(), "file:///t.caffeine", source)
  let params = make_selection_range_params("file:///t.caffeine", [#(0, 0)])

  let assert Ok(result) =
    handlers.handle_request("textDocument/selectionRange", params, ws)
  let response_str = json.to_string(result.response)
  // Should contain range data.
  string.contains(response_str, "range")
  |> should.be_true()
}

// ==== inlay hints ====
// * ✅ returns empty array when no hints

pub fn inlay_hints_empty_test() {
  let ws = open_doc(workspace.new(), "file:///t.caffeine", "")
  let params = make_inlay_hint_params("file:///t.caffeine", 0, 10)

  let assert Ok(result) =
    handlers.handle_request("textDocument/inlayHint", params, ws)
  json.to_string(result.response)
  |> should.equal("[]")
}

// ==== workspace state propagation ====
// * ✅ propagates updated workspace state from blueprint cache

pub fn workspace_state_propagation_test() {
  let ws = open_doc(workspace.new(), "file:///t.caffeine", "")
  let params = make_params("file:///t.caffeine", 0, 0)

  let assert Ok(result) =
    handlers.handle_request("textDocument/hover", params, ws)
  // The handler calls all_validated_blueprints which may update workspace.
  // Just verify we get a valid result with workspace state.
  let _ws2 = result.workspace
  json.to_string(result.response)
  |> should.equal("null")
}

// --- Test helpers ---

/// Build params Dynamic with textDocument.uri and position.
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

/// Build params Dynamic with textDocument.uri, position, and newName.
fn make_rename_params(
  uri: String,
  line: Int,
  character: Int,
  new_name: String,
) -> dynamic.Dynamic {
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
      #("newName", json.string(new_name)),
    ]),
  )
  |> json_to_dynamic
}

/// Build params Dynamic for code action with diagnostics.
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

/// Build params Dynamic for selection range with positions.
fn make_selection_range_params(
  uri: String,
  positions: List(#(Int, Int)),
) -> dynamic.Dynamic {
  json.to_string(
    json.object([
      #("textDocument", json.object([#("uri", json.string(uri))])),
      #(
        "positions",
        json.preprocessed_array(
          list.map(positions, fn(pos) {
            let #(line, character) = pos
            json.object([
              #("line", json.int(line)),
              #("character", json.int(character)),
            ])
          }),
        ),
      ),
    ]),
  )
  |> json_to_dynamic
}

/// Build params Dynamic for inlay hints with range.
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

/// Helper to open a document in workspace state.
fn open_doc(
  ws: workspace.WorkspaceState,
  uri: String,
  content: String,
) -> workspace.WorkspaceState {
  workspace.document_opened(ws, uri, content)
}

/// Helper to parse JSON string to Dynamic.
fn json_to_dynamic(json_str: String) -> dynamic.Dynamic {
  let any_decoder = decode.new_primitive_decoder("any", fn(dyn) { Ok(dyn) })
  let assert Ok(dyn) = json.parse(json_str, any_decoder)
  dyn
}
