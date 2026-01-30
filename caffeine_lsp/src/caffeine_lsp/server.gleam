import caffeine_lang/frontend/formatter
import caffeine_lsp/diagnostics
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

// --- Public API ---

pub fn run() -> Nil {
  init_io()
  log("Caffeine LSP starting...")
  loop(dict.new())
}

// --- Main loop ---

fn loop(docs: Dict(String, String)) -> Nil {
  case read_message() {
    Ok(body) -> {
      case handle_message(body, docs) {
        #(True, new_docs) -> loop(new_docs)
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

fn id_decoder() -> decode.Decoder(Int) {
  use id <- decode.field("id", decode.int)
  decode.success(id)
}

fn uri_from_params() -> decode.Decoder(String) {
  use uri <- decode.subfield(["params", "textDocument", "uri"], decode.string)
  decode.success(uri)
}

fn text_from_did_open() -> decode.Decoder(String) {
  use text <- decode.subfield(
    ["params", "textDocument", "text"],
    decode.string,
  )
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

fn handle_message(
  body: String,
  docs: Dict(String, String),
) -> #(Bool, Dict(String, String)) {
  case json.parse(body, any_decoder()) {
    Ok(dyn) -> dispatch(dyn, docs)
    Error(_) -> {
      log("Failed to parse JSON message")
      #(True, docs)
    }
  }
}

fn dispatch(
  dyn: Dynamic,
  docs: Dict(String, String),
) -> #(Bool, Dict(String, String)) {
  let method = decode.run(dyn, method_decoder())
  let id = case decode.run(dyn, id_decoder()) {
    Ok(n) -> option.Some(n)
    Error(_) -> option.None
  }

  case method {
    Ok("initialize") -> {
      handle_initialize(id)
      #(True, docs)
    }
    Ok("initialized") -> #(True, docs)
    Ok("textDocument/didOpen") -> {
      let new_docs = handle_did_open(dyn, docs)
      #(True, new_docs)
    }
    Ok("textDocument/didChange") -> {
      let new_docs = handle_did_change(dyn, docs)
      #(True, new_docs)
    }
    Ok("textDocument/didClose") -> {
      let new_docs = handle_did_close(dyn, docs)
      #(True, new_docs)
    }
    Ok("textDocument/didSave") -> #(True, docs)
    Ok("textDocument/formatting") -> {
      handle_formatting(dyn, id, docs)
      #(True, docs)
    }
    Ok("shutdown") -> {
      handle_shutdown(id)
      #(False, docs)
    }
    Ok("exit") -> #(False, docs)
    Ok(other) -> {
      log("Unhandled method: " <> other)
      #(True, docs)
    }
    Error(_) -> #(True, docs)
  }
}

// --- Handlers ---

fn handle_initialize(id: Option(Int)) -> Nil {
  let result_json =
    json.object([
      #(
        "capabilities",
        json.object([
          #("textDocumentSync", json.int(1)),
          #("documentFormattingProvider", json.bool(True)),
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
  id: Option(Int),
  docs: Dict(String, String),
) -> Nil {
  let uri_result = decode.run(dyn, uri_from_params())

  case uri_result {
    Ok(uri) -> {
      case dict.get(docs, uri) {
        Ok(text) -> {
          case formatter.format(text) {
            Ok(formatted) -> {
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
                          #("line", json.int(999_999)),
                          #("character", json.int(0)),
                        ]),
                      ),
                    ]),
                  ),
                  #("newText", json.string(formatted)),
                ])
              send_response(id, json.preprocessed_array([edit]))
            }
            Error(_) -> {
              send_response(id, json.preprocessed_array([]))
            }
          }
        }
        Error(_) -> {
          send_response(id, json.preprocessed_array([]))
        }
      }
    }
    Error(_) -> {
      send_response(id, json.preprocessed_array([]))
    }
  }
}

fn handle_shutdown(id: Option(Int)) -> Nil {
  send_response(id, json.null())
}

// --- Diagnostics ---

fn publish_diagnostics(uri: String, text: String) -> Nil {
  let diags = diagnostics.get_diagnostics(text)
  let diags_json =
    json.preprocessed_array(
      list.map(diags, fn(d) { diagnostic_to_json(d) }),
    )
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
            #("character", json.int(d.column)),
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

fn send_response(id: Option(Int), result_json: json.Json) -> Nil {
  let id_json = case id {
    option.Some(n) -> json.int(n)
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

fn log(msg: String) -> Nil {
  write_stderr(msg)
}
