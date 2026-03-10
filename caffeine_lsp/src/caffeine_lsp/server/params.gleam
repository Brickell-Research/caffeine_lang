/// LSP request parameter decoders for extracting typed data from JSON-RPC params.
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode

/// Decode textDocument.uri from params.
pub fn uri(dyn: Dynamic) -> Result(String, Nil) {
  decode.run(dyn, {
    use uri <- decode.subfield(["textDocument", "uri"], decode.string)
    decode.success(uri)
  })
  |> nullify
}

/// Decode position (line, character) from params.
pub fn position(dyn: Dynamic) -> Result(#(Int, Int), Nil) {
  decode.run(dyn, {
    use line <- decode.subfield(["position", "line"], decode.int)
    use character <- decode.subfield(["position", "character"], decode.int)
    decode.success(#(line, character))
  })
  |> nullify
}

/// Decode textDocument.text from didOpen params.
pub fn text_from_did_open(dyn: Dynamic) -> Result(String, Nil) {
  decode.run(dyn, {
    use text <- decode.subfield(["textDocument", "text"], decode.string)
    decode.success(text)
  })
  |> nullify
}

/// Decode text from didChange contentChanges.
pub fn text_from_did_change(dyn: Dynamic) -> Result(String, Nil) {
  decode.run(dyn, {
    let change_item = {
      use text <- decode.field("text", decode.string)
      decode.success(text)
    }
    use changes <- decode.field("contentChanges", decode.list(change_item))
    let text = case changes {
      [first, ..] -> first
      [] -> ""
    }
    decode.success(text)
  })
  |> nullify
}

/// Decode rootUri from initialize params.
pub fn root_uri(dyn: Dynamic) -> Result(String, Nil) {
  let result =
    decode.run(dyn, {
      use uri <- decode.field("rootUri", decode.string)
      decode.success(uri)
    })
  case result {
    Ok(uri) -> Ok(uri)
    Error(_) ->
      decode.run(dyn, {
        use path <- decode.field("rootPath", decode.string)
        decode.success(path)
      })
      |> nullify
  }
}

/// Decode newName from rename params.
pub fn new_name(dyn: Dynamic) -> Result(String, Nil) {
  decode.run(dyn, {
    use name <- decode.field("newName", decode.string)
    decode.success(name)
  })
  |> nullify
}

/// Decode range (start line, end line) from inlay hint params.
pub fn line_range(dyn: Dynamic) -> Result(#(Int, Int), Nil) {
  decode.run(dyn, {
    use start_line <- decode.subfield(["range", "start", "line"], decode.int)
    use end_line <- decode.subfield(["range", "end", "line"], decode.int)
    decode.success(#(start_line, end_line))
  })
  |> nullify
}

/// Decode positions list from selection range params.
pub fn positions(dyn: Dynamic) -> Result(List(#(Int, Int)), Nil) {
  decode.run(dyn, {
    let pos_decoder = {
      use line <- decode.field("line", decode.int)
      use character <- decode.field("character", decode.int)
      decode.success(#(line, character))
    }
    use positions <- decode.field("positions", decode.list(pos_decoder))
    decode.success(positions)
  })
  |> nullify
}

/// Decoded code action diagnostic.
pub type ActionDiagParam {
  ActionDiagParam(
    start_line: Int,
    start_character: Int,
    end_line: Int,
    end_character: Int,
    message: String,
    code: String,
  )
}

/// Decode diagnostics from code action context.
pub fn code_action_diagnostics(
  dyn: Dynamic,
) -> Result(List(ActionDiagParam), Nil) {
  let diag_decoder = {
    use start_line <- decode.subfield(["range", "start", "line"], decode.int)
    use start_character <- decode.subfield(
      ["range", "start", "character"],
      decode.int,
    )
    use end_line <- decode.subfield(["range", "end", "line"], decode.int)
    use end_character <- decode.subfield(
      ["range", "end", "character"],
      decode.int,
    )
    use message <- decode.field("message", decode.string)
    use code <- decode.optional_field("code", "", decode.string)
    decode.success(ActionDiagParam(
      start_line:,
      start_character:,
      end_line:,
      end_character:,
      message:,
      code:,
    ))
  }

  decode.run(dyn, {
    use diagnostics <- decode.subfield(
      ["context", "diagnostics"],
      decode.list(diag_decoder),
    )
    decode.success(diagnostics)
  })
  |> nullify
}

/// Decode query string from workspace symbol params.
pub fn query(dyn: Dynamic) -> Result(String, Nil) {
  decode.run(dyn, {
    use q <- decode.field("query", decode.string)
    decode.success(q)
  })
  |> nullify
}

/// Decode item data from type hierarchy params (supertypes/subtypes).
pub fn type_hierarchy_item(
  dyn: Dynamic,
) -> Result(#(String, Int, Int, Int), Nil) {
  decode.run(dyn, {
    use name <- decode.subfield(["item", "name"], decode.string)
    use line <- decode.subfield(["item", "range", "start", "line"], decode.int)
    use col <- decode.subfield(
      ["item", "range", "start", "character"],
      decode.int,
    )
    use end_col <- decode.subfield(
      ["item", "range", "end", "character"],
      decode.int,
    )
    decode.success(#(name, line, col, end_col - col))
  })
  |> nullify
}

/// Decode changed files from didChangeWatchedFiles params.
pub fn watched_file_changes(dyn: Dynamic) -> Result(List(#(String, Int)), Nil) {
  let change_decoder = {
    use uri <- decode.field("uri", decode.string)
    use change_type <- decode.field("type", decode.int)
    decode.success(#(uri, change_type))
  }
  decode.run(dyn, {
    use changes <- decode.field("changes", decode.list(change_decoder))
    decode.success(changes)
  })
  |> nullify
}

/// Convert any decode error list to a simple Nil error.
fn nullify(result: Result(a, List(decode.DecodeError))) -> Result(a, Nil) {
  case result {
    Ok(value) -> Ok(value)
    Error(_) -> Error(Nil)
  }
}
