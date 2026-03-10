import caffeine_lsp/server/jsonrpc.{Notification, Request}
import gleam/json
import gleeunit/should

// ==== decode_message ====
// * ✅ decodes a request with integer id
// * ✅ decodes a request with string id
// * ✅ decodes a notification (no id)
// * ✅ returns error for invalid JSON
// * ✅ returns error for missing method
// * ✅ decodes request with no params field

pub fn decode_message_request_with_int_id_test() {
  let body =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///test.caffeine\"}}}"

  let result = jsonrpc.decode_message(body)
  let assert Ok(Request(id, method, _params)) = result

  method |> should.equal("textDocument/hover")
  json.to_string(id) |> should.equal("1")
}

pub fn decode_message_request_with_string_id_test() {
  let body =
    "{\"jsonrpc\":\"2.0\",\"id\":\"abc-123\",\"method\":\"shutdown\",\"params\":null}"

  let assert Ok(Request(id, method, _params)) = jsonrpc.decode_message(body)

  method |> should.equal("shutdown")
  json.to_string(id) |> should.equal("\"abc-123\"")
}

pub fn decode_message_notification_test() {
  let body = "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"

  let assert Ok(Notification(method, _params)) = jsonrpc.decode_message(body)

  method |> should.equal("initialized")
}

pub fn decode_message_invalid_json_test() {
  let body = "not valid json"

  jsonrpc.decode_message(body) |> should.be_error()
}

pub fn decode_message_missing_method_test() {
  let body = "{\"jsonrpc\":\"2.0\",\"id\":1}"

  jsonrpc.decode_message(body) |> should.be_error()
}

pub fn decode_message_request_with_no_params_test() {
  let body = "{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"shutdown\"}"

  let assert Ok(Request(id, method, _params)) = jsonrpc.decode_message(body)

  method |> should.equal("shutdown")
  json.to_string(id) |> should.equal("42")
}
