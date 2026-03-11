/// Main LSP server loop — reads JSON-RPC messages from stdin, routes to
/// handlers, and sends responses/notifications back via stdout.
import caffeine_lsp/server/handlers
import caffeine_lsp/server/jsonrpc
import caffeine_lsp/server/notifications
import caffeine_lsp/server/responses
import caffeine_lsp/server/transport
import caffeine_lsp/server/workspace.{type WorkspaceState}
import gleam/dynamic
import gleam/json
import gleam/list
import gleam/option

/// Start the LSP server. Blocks until shutdown.
pub fn start() -> Nil {
  transport.init_io()
  transport.log("caffeine-lsp: starting")
  let ws = workspace.new()
  main_loop(ws)
}

/// Main message loop — tail-recursive.
fn main_loop(ws: WorkspaceState) -> Nil {
  case transport.read_message() {
    Error(_) -> {
      transport.log("caffeine-lsp: stdin closed, exiting")
      Nil
    }
    Ok(body) -> {
      let #(ws2, should_exit) = process_message(ws, body)
      case should_exit {
        True -> Nil
        False -> main_loop(ws2)
      }
    }
  }
}

/// Process a single JSON-RPC message. Returns updated state and exit flag.
fn process_message(ws: WorkspaceState, body: String) -> #(WorkspaceState, Bool) {
  case jsonrpc.decode_message(body) {
    Error(_) -> {
      transport.log("caffeine-lsp: failed to decode message")
      #(ws, False)
    }
    Ok(jsonrpc.Request(id, method, params)) ->
      handle_request(ws, id, method, params)
    Ok(jsonrpc.Notification(method, params)) ->
      handle_notification(ws, method, params)
  }
}

/// Handle a JSON-RPC request — dispatch, respond, return updated state.
fn handle_request(
  ws: WorkspaceState,
  id: json.Json,
  method: String,
  params: dynamic.Dynamic,
) -> #(WorkspaceState, Bool) {
  case method {
    "exit" -> #(ws, True)
    _ -> {
      case
        transport.rescue(fn() { handlers.handle_request(method, params, ws) })
      {
        Ok(Ok(result)) -> {
          jsonrpc.send_response(option.Some(id), result.response)
          let should_exit = method == "shutdown"
          #(result.workspace, should_exit)
        }
        Ok(Error(_)) -> {
          jsonrpc.send_error(option.Some(id), -32_601, "Method not found")
          #(ws, False)
        }
        Error(_) -> {
          transport.log("caffeine-lsp: handler crashed for " <> method)
          jsonrpc.send_error(option.Some(id), -32_603, "Internal error")
          #(ws, False)
        }
      }
    }
  }
}

/// Handle a JSON-RPC notification — dispatch, publish diagnostics.
fn handle_notification(
  ws: WorkspaceState,
  method: String,
  params: dynamic.Dynamic,
) -> #(WorkspaceState, Bool) {
  case method {
    "exit" -> #(ws, True)
    _ -> {
      case
        transport.rescue(fn() {
          notifications.handle_notification(method, params, ws)
        })
      {
        Ok(result) -> {
          list.each(result.diagnostics_to_publish, fn(entry) {
            let #(uri, diags) = entry
            let encoded = responses.encode_publish_diagnostics(uri, diags)
            jsonrpc.send_notification(
              "textDocument/publishDiagnostics",
              encoded,
            )
          })
          #(result.workspace, False)
        }
        Error(_) -> {
          transport.log("caffeine-lsp: notification crashed for " <> method)
          #(ws, False)
        }
      }
    }
  }
}
