import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string

/// A decoded diagnostic from the codeAction request.
pub type ActionDiagnostic {
  ActionDiagnostic(
    line: Int,
    character: Int,
    end_line: Int,
    end_character: Int,
    message: String,
  )
}

/// Decode diagnostics from codeAction params and generate code action JSON.
pub fn get_code_actions(dyn: Dynamic, uri: String) -> List(json.Json) {
  let diags = decode_diagnostics(dyn)
  list.filter_map(diags, fn(d) { diagnostic_to_action(d, uri) })
}

fn decode_diagnostics(dyn: Dynamic) -> List(ActionDiagnostic) {
  let diag_decoder = {
    use line <- decode.subfield(["range", "start", "line"], decode.int)
    use character <- decode.subfield(
      ["range", "start", "character"],
      decode.int,
    )
    use end_line <- decode.subfield(["range", "end", "line"], decode.int)
    use end_character <- decode.subfield(
      ["range", "end", "character"],
      decode.int,
    )
    use message <- decode.field("message", decode.string)
    decode.success(ActionDiagnostic(
      line: line,
      character: character,
      end_line: end_line,
      end_character: end_character,
      message: message,
    ))
  }
  let decoder = {
    use diags <- decode.subfield(
      ["params", "context", "diagnostics"],
      decode.list(diag_decoder),
    )
    decode.success(diags)
  }
  case decode.run(dyn, decoder) {
    Ok(diags) -> diags
    Error(_) -> []
  }
}

fn diagnostic_to_action(
  diag: ActionDiagnostic,
  uri: String,
) -> Result(json.Json, Nil) {
  case string.starts_with(diag.message, "Field names should not be quoted") {
    True -> {
      case extract_between(diag.message, "Use '", "' instead") {
        Ok(name) -> Ok(remove_quotes_action(diag, uri, name))
        Error(_) -> Error(Nil)
      }
    }
    False -> Error(Nil)
  }
}

fn remove_quotes_action(
  diag: ActionDiagnostic,
  uri: String,
  name: String,
) -> json.Json {
  let name_len = string.length(name)
  let edit_range =
    range_json(
      diag.line,
      diag.character,
      diag.line,
      diag.character + name_len + 2,
    )
  let text_edit =
    json.object([
      #("range", edit_range),
      #("newText", json.string(name)),
    ])
  let diag_json =
    json.object([
      #("message", json.string(diag.message)),
      #("source", json.string("caffeine")),
      #(
        "range",
        range_json(diag.line, diag.character, diag.end_line, diag.end_character),
      ),
    ])
  json.object([
    #("title", json.string("Remove quotes from field name")),
    #("kind", json.string("quickfix")),
    #("isPreferred", json.bool(True)),
    #("diagnostics", json.preprocessed_array([diag_json])),
    #(
      "edit",
      json.object([
        #(
          "changes",
          json.object([
            #(uri, json.preprocessed_array([text_edit])),
          ]),
        ),
      ]),
    ),
  ])
}

fn range_json(
  start_line: Int,
  start_char: Int,
  end_line: Int,
  end_char: Int,
) -> json.Json {
  json.object([
    #(
      "start",
      json.object([
        #("line", json.int(start_line)),
        #("character", json.int(start_char)),
      ]),
    ),
    #(
      "end",
      json.object([
        #("line", json.int(end_line)),
        #("character", json.int(end_char)),
      ]),
    ),
  ])
}

fn extract_between(
  s: String,
  prefix: String,
  suffix: String,
) -> Result(String, Nil) {
  case string.split_once(s, prefix) {
    Ok(#(_, after_prefix)) -> {
      case string.split_once(after_prefix, suffix) {
        Ok(#(between, _)) -> Ok(between)
        Error(_) -> Error(Nil)
      }
    }
    Error(_) -> Error(Nil)
  }
}
