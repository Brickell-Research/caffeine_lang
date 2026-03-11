import caffeine_lsp/server/notifications
import caffeine_lsp/server/workspace
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleeunit/should

// ==== handle_notification ====
// * ✅ didOpen opens document and produces diagnostics
// * ✅ didChange updates document and produces diagnostics
// * ✅ didClose clears diagnostics
// * ✅ unknown notification is a no-op

pub fn did_open_test() {
  let ws = workspace.new()
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let params = make_did_open_params("file:///t.caffeine", source)

  let result =
    notifications.handle_notification("textDocument/didOpen", params, ws)

  // Document should be open in workspace.
  workspace.get_document(result.workspace, "file:///t.caffeine")
  |> should.equal(option.Some(source))

  // Should have diagnostics for the URI.
  list.length(result.diagnostics_to_publish)
  |> should.equal(1)
  let assert [#(uri, _diags)] = result.diagnostics_to_publish
  uri |> should.equal("file:///t.caffeine")
}

pub fn did_change_test() {
  let ws = workspace.new()
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  // First open the document.
  let open_params = make_did_open_params("file:///t.caffeine", source)
  let open_result =
    notifications.handle_notification("textDocument/didOpen", open_params, ws)

  // Now change the document.
  let new_source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"y\" }\n"
  let change_params = make_did_change_params("file:///t.caffeine", new_source)
  let result =
    notifications.handle_notification(
      "textDocument/didChange",
      change_params,
      open_result.workspace,
    )

  // Document should be updated.
  workspace.get_document(result.workspace, "file:///t.caffeine")
  |> should.equal(option.Some(new_source))

  // Should have diagnostics.
  { list.length(result.diagnostics_to_publish) >= 1 }
  |> should.be_true()
}

pub fn did_close_test() {
  let ws = workspace.new()
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"

  // Open then close.
  let open_params = make_did_open_params("file:///t.caffeine", source)
  let open_result =
    notifications.handle_notification("textDocument/didOpen", open_params, ws)

  let close_params = make_did_close_params("file:///t.caffeine")
  let result =
    notifications.handle_notification(
      "textDocument/didClose",
      close_params,
      open_result.workspace,
    )

  // Document should no longer be available.
  workspace.get_document(result.workspace, "file:///t.caffeine")
  |> should.equal(option.None)

  // Diagnostics should be cleared (empty list for the URI).
  result.diagnostics_to_publish
  |> should.equal([#("file:///t.caffeine", [])])
}

pub fn unknown_notification_test() {
  let ws = workspace.new()
  let params = make_did_close_params("file:///t.caffeine")

  let result = notifications.handle_notification("unknown/method", params, ws)

  result.diagnostics_to_publish
  |> should.equal([])
}

// ==== compute_diagnostics_for_file ====
// * ✅ returns diagnostics for invalid source
// * ✅ returns empty diagnostics for valid source

pub fn compute_diagnostics_invalid_source_test() {
  let ws = workspace.new()
  let source = "invalid content here"

  let diags =
    notifications.compute_diagnostics_for_file(ws, "file:///t.caffeine", source)

  // Should produce at least one diagnostic for invalid content.
  { list.length(diags) >= 1 }
  |> should.be_true()
}

pub fn compute_diagnostics_with_workspace_context_test() {
  // Set up workspace with a blueprint file open so cross-file checks pass.
  let bp_source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let ws = workspace.new()
  let ws2 = workspace.document_opened(ws, "file:///bp.caffeine", bp_source)
  let #(ws3, _) =
    workspace.update_indices_for_file(ws2, "file:///bp.caffeine", bp_source)

  // Blueprint in context should get dead-blueprint warning (no expectations).
  let diags =
    notifications.compute_diagnostics_for_file(
      ws3,
      "file:///bp.caffeine",
      bp_source,
    )

  // Dead blueprint warnings are expected since no expectations reference it.
  { list.length(diags) >= 1 }
  |> should.be_true()
}

// ==== compute_all_diagnostics ====
// * ✅ computes diagnostics for all open documents

pub fn compute_all_diagnostics_test() {
  let ws = workspace.new()
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let ws2 = workspace.document_opened(ws, "file:///a.caffeine", source)
  let ws3 = workspace.document_opened(ws2, "file:///b.caffeine", source)

  let all_diags = notifications.compute_all_diagnostics(ws3)

  // Should have entries for both files.
  list.length(all_diags)
  |> should.equal(2)
}

// --- Test helpers ---

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
