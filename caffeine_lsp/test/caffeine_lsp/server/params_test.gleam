import caffeine_lsp/server/params
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleeunit/should

// ==== uri ====
// * ✅ decodes textDocument.uri

pub fn uri_test() {
  let dyn =
    json.to_string(
      json.object([
        #(
          "textDocument",
          json.object([#("uri", json.string("file:///test.caffeine"))]),
        ),
      ]),
    )
    |> json_to_dynamic

  params.uri(dyn)
  |> should.equal(Ok("file:///test.caffeine"))
}

// ==== position ====
// * ✅ decodes position

pub fn position_test() {
  let dyn =
    json.to_string(
      json.object([
        #(
          "position",
          json.object([#("line", json.int(5)), #("character", json.int(10))]),
        ),
      ]),
    )
    |> json_to_dynamic

  params.position(dyn)
  |> should.equal(Ok(#(5, 10)))
}

// ==== text_from_did_open ====
// * ✅ decodes text from didOpen

pub fn text_from_did_open_test() {
  let dyn =
    json.to_string(
      json.object([
        #("textDocument", json.object([#("text", json.string("hello world"))])),
      ]),
    )
    |> json_to_dynamic

  params.text_from_did_open(dyn)
  |> should.equal(Ok("hello world"))
}

// ==== text_from_did_change ====
// * ✅ decodes text from didChange

pub fn text_from_did_change_test() {
  let dyn =
    json.to_string(
      json.object([
        #(
          "contentChanges",
          json.preprocessed_array([
            json.object([#("text", json.string("updated"))]),
          ]),
        ),
      ]),
    )
    |> json_to_dynamic

  params.text_from_did_change(dyn)
  |> should.equal(Ok("updated"))
}

// ==== root_uri ====
// * ✅ decodes rootUri
// * ✅ falls back to rootPath

pub fn root_uri_test() {
  let dyn =
    json.to_string(
      json.object([
        #("rootUri", json.string("file:///workspace")),
      ]),
    )
    |> json_to_dynamic

  params.root_uri(dyn)
  |> should.equal(Ok("file:///workspace"))
}

pub fn root_uri_fallback_test() {
  let dyn =
    json.to_string(
      json.object([
        #("rootPath", json.string("/workspace")),
      ]),
    )
    |> json_to_dynamic

  params.root_uri(dyn)
  |> should.equal(Ok("/workspace"))
}

// ==== new_name ====
// * ✅ decodes newName

pub fn new_name_test() {
  let dyn =
    json.to_string(json.object([#("newName", json.string("renamed"))]))
    |> json_to_dynamic

  params.new_name(dyn)
  |> should.equal(Ok("renamed"))
}

// ==== line_range ====
// * ✅ decodes range lines

pub fn line_range_test() {
  let dyn =
    json.to_string(
      json.object([
        #(
          "range",
          json.object([
            #(
              "start",
              json.object([#("line", json.int(2)), #("character", json.int(0))]),
            ),
            #(
              "end",
              json.object([#("line", json.int(10)), #("character", json.int(0))]),
            ),
          ]),
        ),
      ]),
    )
    |> json_to_dynamic

  params.line_range(dyn)
  |> should.equal(Ok(#(2, 10)))
}

// ==== query ====
// * ✅ decodes query string

pub fn query_test() {
  let dyn =
    json.to_string(json.object([#("query", json.string("search"))]))
    |> json_to_dynamic

  params.query(dyn)
  |> should.equal(Ok("search"))
}

// ==== code_action_diagnostics ====
// * ✅ decodes diagnostic list from context

pub fn code_action_diagnostics_test() {
  let dyn =
    json.to_string(
      json.object([
        #(
          "context",
          json.object([
            #(
              "diagnostics",
              json.preprocessed_array([
                json.object([
                  #(
                    "range",
                    json.object([
                      #(
                        "start",
                        json.object([
                          #("line", json.int(1)),
                          #("character", json.int(2)),
                        ]),
                      ),
                      #(
                        "end",
                        json.object([
                          #("line", json.int(1)),
                          #("character", json.int(10)),
                        ]),
                      ),
                    ]),
                  ),
                  #("message", json.string("test error")),
                  #("code", json.string("quoted-field-name")),
                ]),
              ]),
            ),
          ]),
        ),
      ]),
    )
    |> json_to_dynamic

  let assert Ok([diag]) = params.code_action_diagnostics(dyn)
  diag.start_line |> should.equal(1)
  diag.start_character |> should.equal(2)
  diag.end_line |> should.equal(1)
  diag.end_character |> should.equal(10)
  diag.message |> should.equal("test error")
  diag.code |> should.equal("quoted-field-name")
}

/// Helper to parse JSON string to Dynamic.
fn json_to_dynamic(json_str: String) -> dynamic.Dynamic {
  let any_decoder = decode.new_primitive_decoder("any", fn(dyn) { Ok(dyn) })
  let assert Ok(dyn) = json.parse(json_str, any_decoder)
  dyn
}
