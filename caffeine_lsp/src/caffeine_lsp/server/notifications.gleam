/// LSP notification handlers — document lifecycle and diagnostic publishing.
import caffeine_lsp/diagnostics.{type Diagnostic}
import caffeine_lsp/linker_diagnostics
import caffeine_lsp/server/params
import caffeine_lsp/server/workspace.{type WorkspaceState}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/list

/// Result of handling a notification — updated state and diagnostics to publish.
pub type NotifyResult {
  NotifyResult(
    workspace: WorkspaceState,
    diagnostics_to_publish: List(#(String, List(Diagnostic))),
  )
}

/// Route an LSP notification to the appropriate handler.
/// Returns the original state unchanged for unrecognized notifications.
pub fn handle_notification(
  method: String,
  params: Dynamic,
  ws: WorkspaceState,
) -> NotifyResult {
  case method {
    "textDocument/didOpen" -> handle_did_open(ws, params)
    "textDocument/didChange" -> handle_did_change(ws, params)
    "textDocument/didClose" -> handle_did_close(ws, params)
    "initialized" -> NotifyResult(ws, [])
    _ -> NotifyResult(ws, [])
  }
}

// --- Notification handlers ---

fn handle_did_open(ws: WorkspaceState, params: Dynamic) -> NotifyResult {
  case params.uri(params), params.text_from_did_open(params) {
    Ok(uri), Ok(text) -> {
      let ws2 = workspace.document_opened(ws, uri, text)
      let #(ws3, _changed) = workspace.update_indices_for_file(ws2, uri, text)
      let diags = compute_diagnostics_for_file(ws3, uri, text)
      NotifyResult(ws3, [#(uri, diags)])
    }
    _, _ -> NotifyResult(ws, [])
  }
}

fn handle_did_change(ws: WorkspaceState, params: Dynamic) -> NotifyResult {
  case params.uri(params), params.text_from_did_change(params) {
    Ok(uri), Ok(text) -> {
      let ws2 = workspace.document_changed(ws, uri, text)
      let #(ws3, indices_changed) =
        workspace.update_indices_for_file(ws2, uri, text)
      case indices_changed {
        True -> {
          // Index change — revalidate all open documents.
          let all_diags = compute_all_diagnostics(ws3)
          NotifyResult(ws3, all_diags)
        }
        False -> {
          // No index change — only revalidate this document.
          let diags = compute_diagnostics_for_file(ws3, uri, text)
          NotifyResult(ws3, [#(uri, diags)])
        }
      }
    }
    _, _ -> NotifyResult(ws, [])
  }
}

fn handle_did_close(ws: WorkspaceState, params: Dynamic) -> NotifyResult {
  case params.uri(params) {
    Ok(uri) -> {
      let ws2 = workspace.document_closed(ws, uri)
      // Clear diagnostics for closed document.
      NotifyResult(ws2, [#(uri, [])])
    }
    Error(_) -> NotifyResult(ws, [])
  }
}

// --- Diagnostic computation ---

/// Compute all diagnostics for a single file.
pub fn compute_diagnostics_for_file(
  ws: WorkspaceState,
  _uri: String,
  text: String,
) -> List(Diagnostic) {
  let known_blueprints = workspace.all_known_blueprints(ws)
  let known_identifiers = workspace.all_known_expectation_identifiers(ws)
  let referenced_blueprints = workspace.all_referenced_blueprints(ws)
  let #(_, validated_blueprints) = workspace.all_validated_blueprints(ws)

  // Frontend diagnostics (parse, validation, cross-file blueprint/dependency).
  let frontend_diags =
    diagnostics.get_all_diagnostics(text, known_blueprints, known_identifiers)

  // Linker diagnostics (type checking against validated blueprints).
  let linker_diags =
    linker_diagnostics.get_linker_diagnostics(text, validated_blueprints)

  // Dead blueprint diagnostics (blueprints with no expectations).
  let dead_diags =
    diagnostics.get_dead_blueprint_diagnostics(text, referenced_blueprints)

  list.flatten([frontend_diags, linker_diags, dead_diags])
}

/// Compute diagnostics for all open documents.
pub fn compute_all_diagnostics(
  ws: WorkspaceState,
) -> List(#(String, List(Diagnostic))) {
  ws.documents
  |> dict.to_list
  |> list.map(fn(entry) {
    let #(uri, text) = entry
    #(uri, compute_diagnostics_for_file(ws, uri, text))
  })
}
