import gleam/json

/// Build a LSP Position JSON object from a line and character offset.
@internal
pub fn position_json(line: Int, character: Int) -> json.Json {
  json.object([
    #("line", json.int(line)),
    #("character", json.int(character)),
  ])
}

/// Build a LSP Range JSON object from start and end line/character pairs.
@internal
pub fn range_json(
  start_line: Int,
  start_character: Int,
  end_line: Int,
  end_character: Int,
) -> json.Json {
  json.object([
    #("start", position_json(start_line, start_character)),
    #("end", position_json(end_line, end_character)),
  ])
}
