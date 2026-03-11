/// JSON-RPC 2.0 protocol types and codec for the LSP server.
import caffeine_lsp/server/transport
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option}

/// A parsed JSON-RPC message.
pub type Message {
  /// A request with an id that expects a response.
  Request(id: json.Json, method: String, params: Dynamic)
  /// A notification with no id (no response expected).
  Notification(method: String, params: Dynamic)
}

/// Decode a raw JSON string into a JSON-RPC message.
pub fn decode_message(body: String) -> Result(Message, Nil) {
  let any_decoder = decode.new_primitive_decoder("any", fn(dyn) { Ok(dyn) })

  case json.parse(body, any_decoder) {
    Ok(dyn) -> {
      let method_result =
        decode.run(dyn, {
          use method <- decode.field("method", decode.string)
          decode.success(method)
        })

      let id_result = decode.run(dyn, id_decoder())

      let params = case
        decode.run(dyn, {
          use p <- decode.field("params", any_decoder)
          decode.success(p)
        })
      {
        Ok(p) -> p
        Error(_) -> dynamic.nil()
      }

      case method_result, id_result {
        Ok(method), Ok(id) -> Ok(Request(id:, method:, params:))
        Ok(method), Error(_) -> Ok(Notification(method:, params:))
        Error(_), _ -> Error(Nil)
      }
    }
    Error(_) -> Error(Nil)
  }
}

/// Decode a JSON-RPC id field (may be int or string).
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

// --- Response encoding ---

/// Send a successful JSON-RPC response.
pub fn send_response(id: Option(json.Json), result: json.Json) -> Nil {
  let id_json = case id {
    option.Some(id_val) -> id_val
    option.None -> json.null()
  }
  let msg =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", id_json),
      #("result", result),
    ])
  transport.send_raw(json.to_string(msg))
}

/// Send a JSON-RPC error response.
pub fn send_error(id: Option(json.Json), code: Int, message: String) -> Nil {
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
  transport.send_raw(json.to_string(msg))
}

/// Send a JSON-RPC notification (no id, no response expected).
pub fn send_notification(method: String, params: json.Json) -> Nil {
  let msg =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("method", json.string(method)),
      #("params", params),
    ])
  transport.send_raw(json.to_string(msg))
}
