import caffeine_lang/frontend/formatter
import caffeine_lsp/code_actions
import caffeine_lsp/completion
import caffeine_lsp/definition
import caffeine_lsp/diagnostics
import caffeine_lsp/document_symbols
import caffeine_lsp/hover
import caffeine_lsp/semantic_tokens
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string

// --- FFI bindings ---

@external(erlang, "caffeine_lsp_ffi", "init_io")
@external(javascript, "../caffeine_lsp_ffi.mjs", "init_io")
fn init_io() -> Nil

@external(erlang, "caffeine_lsp_ffi", "read_line")
@external(javascript, "../caffeine_lsp_ffi.mjs", "read_line")
fn read_line() -> Result(String, Nil)

@external(erlang, "caffeine_lsp_ffi", "read_bytes")
@external(javascript, "../caffeine_lsp_ffi.mjs", "read_bytes")
fn read_bytes(n: Int) -> Result(String, Nil)

@external(erlang, "caffeine_lsp_ffi", "write_stdout")
@external(javascript, "../caffeine_lsp_ffi.mjs", "write_stdout")
fn write_stdout(data: String) -> Nil

@external(erlang, "caffeine_lsp_ffi", "write_stderr")
@external(javascript, "../caffeine_lsp_ffi.mjs", "write_stderr")
fn write_stderr(data: String) -> Nil

@external(erlang, "caffeine_lsp_ffi", "rescue")
@external(javascript, "../caffeine_lsp_ffi.mjs", "rescue")
fn rescue(f: fn() -> a) -> Result(a, Nil)

// --- Server state ---

type ServerState {
  ServerState(docs: Dict(String, String), initialized: Bool, shutdown: Bool)
}

// --- Public API ---

pub fn run() -> Nil {
  init_io()
  log("Caffeine LSP starting...")
  loop(ServerState(docs: dict.new(), initialized: False, shutdown: False))
}

// --- Main loop ---

fn loop(state: ServerState) -> Nil {
  case read_message() {
    Ok(body) -> {
      case handle_message(body, state) {
        #(True, new_state) -> loop(new_state)
        #(False, _) -> Nil
      }
    }
    Error(_) -> Nil
  }
}

// --- Message reading (LSP base protocol) ---

fn read_message() -> Result(String, Nil) {
  use content_length <- result.try(read_headers(option.None))
  read_bytes(content_length)
}

fn read_headers(content_length: Option(Int)) -> Result(Int, Nil) {
  use line <- result.try(read_line())
  let trimmed = string.trim(line)
  case trimmed {
    "" -> {
      case content_length {
        option.Some(n) -> Ok(n)
        option.None -> Error(Nil)
      }
    }
    _ -> {
      let new_cl = case string.starts_with(trimmed, "Content-Length: ") {
        True -> {
          let n_str =
            string.replace(in: trimmed, each: "Content-Length: ", with: "")
          case int.parse(n_str) {
            Ok(n) -> option.Some(n)
            Error(_) -> content_length
          }
        }
        False -> content_length
      }
      read_headers(new_cl)
    }
  }
}

// --- Decoders ---

fn any_decoder() -> decode.Decoder(Dynamic) {
  decode.new_primitive_decoder("any", fn(dyn) { Ok(dyn) })
}

fn method_decoder() -> decode.Decoder(String) {
  use method <- decode.field("method", decode.string)
  decode.success(method)
}

fn id_decoder() -> decode.Decoder(json.Json) {
  let id_value_decoder =
    decode.new_primitive_decoder("id", fn(dyn) {
      case decode.run(dyn, decode.int) {
        Ok(n) -> Ok(json.int(n))
        Error(_) ->
          case decode.run(dyn, decode.string) {
            Ok(s) -> Ok(json.string(s))
            Error(_) -> Error(json.null())
          }
      }
    })
  use id <- decode.field("id", id_value_decoder)
  decode.success(id)
}

fn uri_from_params() -> decode.Decoder(String) {
  use uri <- decode.subfield(["params", "textDocument", "uri"], decode.string)
  decode.success(uri)
}

fn position_from_params() -> decode.Decoder(#(Int, Int)) {
  use line <- decode.subfield(["params", "position", "line"], decode.int)
  use character <- decode.subfield(
    ["params", "position", "character"],
    decode.int,
  )
  decode.success(#(line, character))
}

fn text_from_did_open() -> decode.Decoder(String) {
  use text <- decode.subfield(["params", "textDocument", "text"], decode.string)
  decode.success(text)
}

fn text_from_did_change() -> decode.Decoder(String) {
  let change_item = {
    use text <- decode.field("text", decode.string)
    decode.success(text)
  }
  use changes <- decode.subfield(
    ["params", "contentChanges"],
    decode.list(change_item),
  )
  let text = case changes {
    [first, ..] -> first
    [] -> ""
  }
  decode.success(text)
}

// --- Message handling ---

fn handle_message(body: String, state: ServerState) -> #(Bool, ServerState) {
  case json.parse(body, any_decoder()) {
    Ok(dyn) -> {
      // Extract the request ID early so we can send error responses on crash
      let id = case decode.run(dyn, id_decoder()) {
        Ok(id_json) -> option.Some(id_json)
        Error(_) -> option.None
      }
      case rescue(fn() { dispatch(dyn, id, state) }) {
        Ok(result) -> result
        Error(_) -> {
          // Handler crashed — send error response if this was a request
          case id {
            option.Some(_) -> send_error(id, -32_603, "Internal error")
            option.None -> Nil
          }
          #(True, state)
        }
      }
    }
    Error(_) -> {
      log("Failed to parse JSON message")
      #(True, state)
    }
  }
}

fn dispatch(
  dyn: Dynamic,
  id: Option(json.Json),
  state: ServerState,
) -> #(Bool, ServerState) {
  let method = decode.run(dyn, method_decoder())

  case method {
    Ok(m) -> log("-> " <> m)
    Error(_) -> log("-> (unknown method)")
  }

  // Handle lifecycle methods regardless of state
  case method {
    Ok("initialize") -> {
      handle_initialize(id)
      #(True, ServerState(..state, initialized: True))
    }
    Ok("initialized") -> #(True, state)
    Ok("exit") -> #(False, state)
    Ok("shutdown") -> {
      handle_shutdown(id)
      #(False, ServerState(..state, shutdown: True))
    }
    // After shutdown, reject everything except exit
    _ if state.shutdown -> {
      case id {
        option.Some(_) -> send_error(id, -32_600, "Server is shutting down")
        option.None -> Nil
      }
      #(True, state)
    }
    // Before initialization, reject non-lifecycle requests
    _ if !state.initialized -> {
      case id {
        option.Some(_) -> send_error(id, -32_002, "Server not initialized")
        option.None -> Nil
      }
      #(True, state)
    }
    // Normal dispatch after initialization
    Ok("textDocument/didOpen") -> {
      let new_docs = handle_did_open(dyn, state.docs)
      #(True, ServerState(..state, docs: new_docs))
    }
    Ok("textDocument/didChange") -> {
      let new_docs = handle_did_change(dyn, state.docs)
      #(True, ServerState(..state, docs: new_docs))
    }
    Ok("textDocument/didClose") -> {
      let new_docs = handle_did_close(dyn, state.docs)
      #(True, ServerState(..state, docs: new_docs))
    }
    Ok("textDocument/didSave") -> #(True, state)
    Ok("$/cancelRequest") -> #(True, state)
    Ok("$/setTrace") -> #(True, state)
    Ok("textDocument/willSave") -> #(True, state)
    Ok("textDocument/formatting") -> {
      handle_formatting(dyn, id, state.docs)
      #(True, state)
    }
    Ok("textDocument/documentSymbol") -> {
      handle_document_symbol(dyn, id, state.docs)
      #(True, state)
    }
    Ok("textDocument/hover") -> {
      handle_hover(dyn, id, state.docs)
      #(True, state)
    }
    Ok("textDocument/completion") -> {
      handle_completion(dyn, id, state.docs)
      #(True, state)
    }
    Ok("textDocument/codeAction") -> {
      handle_code_action(dyn, id)
      #(True, state)
    }
    Ok("textDocument/semanticTokens/full") -> {
      handle_semantic_tokens(dyn, id, state.docs)
      #(True, state)
    }
    Ok("textDocument/definition") -> {
      handle_definition(dyn, id, state.docs)
      #(True, state)
    }
    Ok(other) -> {
      log("Unhandled method: " <> other)
      case id {
        option.Some(_) -> send_error(id, -32_601, "Method not found: " <> other)
        option.None -> Nil
      }
      #(True, state)
    }
    Error(_) -> {
      case id {
        option.Some(_) -> send_error(id, -32_600, "Invalid request")
        option.None -> Nil
      }
      #(True, state)
    }
  }
}

// --- Handlers ---

fn handle_initialize(id: Option(json.Json)) -> Nil {
  let result_json =
    json.object([
      #(
        "capabilities",
        json.object([
          #("textDocumentSync", json.int(1)),
          #("documentFormattingProvider", json.bool(True)),
          #("documentSymbolProvider", json.bool(True)),
          #("hoverProvider", json.bool(True)),
          #("definitionProvider", json.bool(True)),
          #(
            "completionProvider",
            json.object([
              #(
                "triggerCharacters",
                json.preprocessed_array([
                  json.string(":"),
                  json.string("["),
                ]),
              ),
            ]),
          ),
          #(
            "codeActionProvider",
            json.object([
              #(
                "codeActionKinds",
                json.preprocessed_array([json.string("quickfix")]),
              ),
            ]),
          ),
          #(
            "semanticTokensProvider",
            json.object([
              #(
                "legend",
                json.object([
                  #(
                    "tokenTypes",
                    json.preprocessed_array(list.map(
                      semantic_tokens.token_types,
                      json.string,
                    )),
                  ),
                  #("tokenModifiers", json.preprocessed_array([])),
                ]),
              ),
              #("full", json.bool(True)),
            ]),
          ),
        ]),
      ),
      #(
        "serverInfo",
        json.object([
          #("name", json.string("caffeine-lsp")),
          #("version", json.string("0.1.0")),
        ]),
      ),
    ])
  send_response(id, result_json)
}

fn handle_did_open(
  dyn: Dynamic,
  docs: Dict(String, String),
) -> Dict(String, String) {
  let uri_result = decode.run(dyn, uri_from_params())
  let text_result = decode.run(dyn, text_from_did_open())

  case uri_result, text_result {
    Ok(uri), Ok(text) -> {
      publish_diagnostics(uri, text)
      dict.insert(docs, uri, text)
    }
    _, _ -> {
      log("Failed to extract uri/text from didOpen")
      docs
    }
  }
}

fn handle_did_change(
  dyn: Dynamic,
  docs: Dict(String, String),
) -> Dict(String, String) {
  let uri_result = decode.run(dyn, uri_from_params())
  let text_result = decode.run(dyn, text_from_did_change())

  case uri_result, text_result {
    Ok(uri), Ok(text) -> {
      publish_diagnostics(uri, text)
      dict.insert(docs, uri, text)
    }
    _, _ -> {
      log("Failed to extract uri/text from didChange")
      docs
    }
  }
}

fn handle_did_close(
  dyn: Dynamic,
  docs: Dict(String, String),
) -> Dict(String, String) {
  let uri_result = decode.run(dyn, uri_from_params())

  case uri_result {
    Ok(uri) -> {
      send_notification(
        "textDocument/publishDiagnostics",
        json.object([
          #("uri", json.string(uri)),
          #("diagnostics", json.preprocessed_array([])),
        ]),
      )
      dict.delete(docs, uri)
    }
    Error(_) -> {
      log("Failed to extract uri from didClose")
      docs
    }
  }
}

fn handle_formatting(
  dyn: Dynamic,
  id: Option(json.Json),
  docs: Dict(String, String),
) -> Nil {
  let empty = json.preprocessed_array([])
  with_document(dyn, id, docs, empty, fn(text) {
    case formatter.format(text) {
      Ok(formatted) -> {
        let line_count = list.length(string.split(text, "\n"))
        let edit =
          json.object([
            #(
              "range",
              json.object([
                #(
                  "start",
                  json.object([
                    #("line", json.int(0)),
                    #("character", json.int(0)),
                  ]),
                ),
                #(
                  "end",
                  json.object([
                    #("line", json.int(line_count)),
                    #("character", json.int(0)),
                  ]),
                ),
              ]),
            ),
            #("newText", json.string(formatted)),
          ])
        json.preprocessed_array([edit])
      }
      Error(_) -> empty
    }
  })
}

fn handle_document_symbol(
  dyn: Dynamic,
  id: Option(json.Json),
  docs: Dict(String, String),
) -> Nil {
  with_document(dyn, id, docs, json.preprocessed_array([]), fn(text) {
    json.preprocessed_array(document_symbols.get_symbols(text))
  })
}

fn handle_semantic_tokens(
  dyn: Dynamic,
  id: Option(json.Json),
  docs: Dict(String, String),
) -> Nil {
  let empty = json.object([#("data", json.preprocessed_array([]))])
  with_document(dyn, id, docs, empty, fn(text) {
    let data = semantic_tokens.get_semantic_tokens(text)
    json.object([#("data", json.preprocessed_array(data))])
  })
}

fn handle_code_action(dyn: Dynamic, id: Option(json.Json)) -> Nil {
  let uri_result = decode.run(dyn, uri_from_params())
  case uri_result {
    Ok(uri) -> {
      case rescue(fn() { code_actions.get_code_actions(dyn, uri) }) {
        Ok(actions) -> send_response(id, json.preprocessed_array(actions))
        Error(_) -> send_response(id, json.preprocessed_array([]))
      }
    }
    Error(_) -> send_response(id, json.preprocessed_array([]))
  }
}

fn handle_completion(
  dyn: Dynamic,
  id: Option(json.Json),
  docs: Dict(String, String),
) -> Nil {
  let empty = json.preprocessed_array([])
  let uri_result = decode.run(dyn, uri_from_params())
  let pos_result = decode.run(dyn, position_from_params())
  case uri_result, pos_result {
    Ok(uri), Ok(#(line, character)) -> {
      let text = case dict.get(docs, uri) {
        Ok(t) -> t
        Error(_) -> ""
      }
      case rescue(fn() { completion.get_completions(text, line, character) }) {
        Ok(items) -> send_response(id, json.preprocessed_array(items))
        Error(_) -> send_response(id, empty)
      }
    }
    _, _ -> {
      case rescue(fn() { completion.get_completions("", 0, 0) }) {
        Ok(items) -> send_response(id, json.preprocessed_array(items))
        Error(_) -> send_response(id, empty)
      }
    }
  }
}

fn handle_hover(
  dyn: Dynamic,
  id: Option(json.Json),
  docs: Dict(String, String),
) -> Nil {
  let uri_result = decode.run(dyn, uri_from_params())
  let pos_result = decode.run(dyn, position_from_params())

  case uri_result, pos_result {
    Ok(uri), Ok(#(line, character)) -> {
      case dict.get(docs, uri) {
        Ok(text) -> {
          case rescue(fn() { hover.get_hover(text, line, character) }) {
            Ok(option.Some(hover_json)) -> send_response(id, hover_json)
            _ -> send_response(id, json.null())
          }
        }
        Error(_) -> send_response(id, json.null())
      }
    }
    _, _ -> send_response(id, json.null())
  }
}

fn handle_definition(
  dyn: Dynamic,
  id: Option(json.Json),
  docs: Dict(String, String),
) -> Nil {
  let uri_result = decode.run(dyn, uri_from_params())
  let pos_result = decode.run(dyn, position_from_params())

  case uri_result, pos_result {
    Ok(uri), Ok(#(line, character)) -> {
      case dict.get(docs, uri) {
        Ok(text) -> {
          case
            rescue(fn() { definition.get_definition(text, line, character) })
          {
            Ok(option.Some(#(def_line, def_col, name_len))) ->
              send_response(
                id,
                json.object([
                  #("uri", json.string(uri)),
                  #(
                    "range",
                    json.object([
                      #(
                        "start",
                        json.object([
                          #("line", json.int(def_line)),
                          #("character", json.int(def_col)),
                        ]),
                      ),
                      #(
                        "end",
                        json.object([
                          #("line", json.int(def_line)),
                          #("character", json.int(def_col + name_len)),
                        ]),
                      ),
                    ]),
                  ),
                ]),
              )
            _ -> send_response(id, json.null())
          }
        }
        Error(_) -> send_response(id, json.null())
      }
    }
    _, _ -> send_response(id, json.null())
  }
}

fn handle_shutdown(id: Option(json.Json)) -> Nil {
  send_response(id, json.null())
}

// --- Diagnostics ---

fn publish_diagnostics(uri: String, text: String) -> Nil {
  let diags = case rescue(fn() { diagnostics.get_diagnostics(text) }) {
    Ok(d) -> d
    Error(_) -> []
  }
  let diags_json =
    json.preprocessed_array(list.map(diags, fn(d) { diagnostic_to_json(d) }))
  send_notification(
    "textDocument/publishDiagnostics",
    json.object([
      #("uri", json.string(uri)),
      #("diagnostics", diags_json),
    ]),
  )
}

fn diagnostic_to_json(d: diagnostics.Diagnostic) -> json.Json {
  json.object([
    #(
      "range",
      json.object([
        #(
          "start",
          json.object([
            #("line", json.int(d.line)),
            #("character", json.int(d.column)),
          ]),
        ),
        #(
          "end",
          json.object([
            #("line", json.int(d.line)),
            #("character", json.int(d.end_column)),
          ]),
        ),
      ]),
    ),
    #("severity", json.int(d.severity)),
    #("source", json.string("caffeine")),
    #("message", json.string(d.message)),
  ])
}

// --- JSON-RPC transport ---

fn send_response(id: Option(json.Json), result_json: json.Json) -> Nil {
  let id_str = case id {
    option.Some(id_val) -> json.to_string(id_val)
    option.None -> "null"
  }
  log("<- response id=" <> id_str)
  let id_json = case id {
    option.Some(id_val) -> id_val
    option.None -> json.null()
  }
  let msg =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", id_json),
      #("result", result_json),
    ])
  send_raw(json.to_string(msg))
}

fn send_error(id: Option(json.Json), code: Int, message: String) -> Nil {
  let id_json = case id {
    option.Some(id_val) -> id_val
    option.None -> json.null()
  }
  let msg =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", id_json),
      #(
        "error",
        json.object([
          #("code", json.int(code)),
          #("message", json.string(message)),
        ]),
      ),
    ])
  send_raw(json.to_string(msg))
}

fn send_notification(method: String, params: json.Json) -> Nil {
  let msg =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("method", json.string(method)),
      #("params", params),
    ])
  send_raw(json.to_string(msg))
}

fn send_raw(body: String) -> Nil {
  let body_bytes = <<body:utf8>>
  let length = bit_array.byte_size(body_bytes)
  let header = "Content-Length: " <> int.to_string(length) <> "\r\n\r\n"
  write_stdout(header <> body)
}

// --- Helpers ---

/// Decode URI, look up document text, call handler, send response.
/// Falls back to on_error if URI decode or doc lookup fails.
fn with_document(
  dyn: Dynamic,
  id: Option(json.Json),
  docs: Dict(String, String),
  on_error: json.Json,
  handler: fn(String) -> json.Json,
) -> Nil {
  case decode.run(dyn, uri_from_params()) {
    Ok(uri) ->
      case dict.get(docs, uri) {
        Ok(text) ->
          case rescue(fn() { handler(text) }) {
            Ok(result) -> send_response(id, result)
            Error(_) -> send_response(id, on_error)
          }
        Error(_) -> send_response(id, on_error)
      }
    Error(_) -> send_response(id, on_error)
  }
}

fn log(msg: String) -> Nil {
  write_stderr(msg)
}
