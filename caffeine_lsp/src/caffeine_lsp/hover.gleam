import caffeine_lang/common/collection_types
import caffeine_lang/common/modifier_types
import caffeine_lang/common/primitive_types
import caffeine_lang/common/refinement_types
import caffeine_lang/common/type_info.{type TypeMeta}
import caffeine_lsp/keyword_info
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// Returns hover JSON for the word at the given position, or None.
pub fn get_hover(
  content: String,
  line: Int,
  character: Int,
) -> Option(json.Json) {
  let word = extract_word_at(content, line, character)
  case word {
    "" -> option.None
    w ->
      case lookup_hover(w) {
        option.Some(markdown) ->
          option.Some(
            json.object([
              #(
                "contents",
                json.object([
                  #("kind", json.string("markdown")),
                  #("value", json.string(markdown)),
                ]),
              ),
            ]),
          )
        option.None -> option.None
      }
  }
}

/// Look up hover documentation for a token name.
fn lookup_hover(word: String) -> Option(String) {
  let all_metas =
    list.flatten([
      primitive_types.all_type_metas(),
      collection_types.all_type_metas(),
      modifier_types.all_type_metas(),
      refinement_types.all_type_metas(),
    ])
  case list.find(all_metas, fn(m: TypeMeta) { m.name == word }) {
    Ok(meta) -> option.Some(format_type_meta(meta))
    Error(_) -> lookup_keyword(word)
  }
}

fn format_type_meta(meta: TypeMeta) -> String {
  "**"
  <> meta.name
  <> "** — "
  <> meta.description
  <> "\n\n"
  <> "Syntax: `"
  <> meta.syntax
  <> "`\n\n"
  <> "Example: `"
  <> meta.example
  <> "`"
}

fn lookup_keyword(word: String) -> Option(String) {
  case
    list.find(keyword_info.all_keywords(), fn(kw) { kw.name == word })
  {
    Ok(kw) -> option.Some("**" <> kw.name <> "** — " <> kw.description)
    Error(_) -> option.None
  }
}

/// Extract the word under the cursor at the given 0-indexed line and character.
fn extract_word_at(content: String, line: Int, character: Int) -> String {
  let lines = string.split(content, "\n")
  case list.drop(lines, line) {
    [line_text, ..] -> word_at_column(line_text, character)
    [] -> ""
  }
}

fn word_at_column(line: String, col: Int) -> String {
  let graphemes = string.to_graphemes(line)
  let start = scan_word_start(graphemes, col, 0, col)
  let end = scan_word_end(graphemes, col, 0)
  graphemes
  |> list.drop(start)
  |> list.take(end - start)
  |> string.join("")
}

fn scan_word_start(
  graphemes: List(String),
  col: Int,
  idx: Int,
  last_start: Int,
) -> Int {
  case graphemes {
    [] -> last_start
    [g, ..rest] -> {
      case idx >= col {
        True -> last_start
        False -> {
          let new_start = case is_word_char(g) {
            True -> last_start
            False -> idx + 1
          }
          scan_word_start(rest, col, idx + 1, new_start)
        }
      }
    }
  }
}

fn scan_word_end(graphemes: List(String), col: Int, idx: Int) -> Int {
  case graphemes {
    [] -> idx
    [g, ..rest] -> {
      case idx > col && !is_word_char(g) {
        True -> idx
        False -> scan_word_end(rest, col, idx + 1)
      }
    }
  }
}

fn is_word_char(g: String) -> Bool {
  case g {
    "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j" | "k" | "l"
    | "m" | "n" | "o" | "p" | "q" | "r" | "s" | "t" | "u" | "v" | "w" | "x"
    | "y" | "z"
    -> True
    "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" | "I" | "J" | "K" | "L"
    | "M" | "N" | "O" | "P" | "Q" | "R" | "S" | "T" | "U" | "V" | "W" | "X"
    | "Y" | "Z"
    -> True
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    "_" -> True
    _ -> False
  }
}
