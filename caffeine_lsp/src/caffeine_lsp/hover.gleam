import caffeine_lang/common/accepted_types
import caffeine_lang/common/collection_types
import caffeine_lang/common/modifier_types
import caffeine_lang/common/primitive_types
import caffeine_lang/common/refinement_types
import caffeine_lang/common/type_info.{type TypeMeta}
import caffeine_lang/frontend/ast
import caffeine_lsp/file_utils
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
      case lookup_hover(w, content) {
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
/// Checks built-in types, keywords, then user-defined symbols.
fn lookup_hover(word: String, content: String) -> Option(String) {
  let all_metas =
    list.flatten([
      primitive_types.all_type_metas(),
      collection_types.all_type_metas(),
      modifier_types.all_type_metas(),
      refinement_types.all_type_metas(),
    ])
  case list.find(all_metas, fn(m: TypeMeta) { m.name == word }) {
    Ok(meta) -> option.Some(format_type_meta(meta))
    Error(_) ->
      case lookup_keyword(word) {
        option.Some(kw) -> option.Some(kw)
        option.None -> lookup_user_defined(word, content)
      }
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
  case list.find(keyword_info.all_keywords(), fn(kw) { kw.name == word }) {
    Ok(kw) -> option.Some("**" <> kw.name <> "** — " <> kw.description)
    Error(_) -> option.None
  }
}

/// Look up user-defined extendables and type aliases in the current file.
fn lookup_user_defined(word: String, content: String) -> Option(String) {
  case file_utils.parse(content) {
    Ok(file_utils.Blueprints(file)) -> {
      case lookup_extendable(word, file.extendables) {
        option.Some(md) -> option.Some(md)
        option.None -> lookup_type_alias(word, file.type_aliases)
      }
    }
    Ok(file_utils.Expects(file)) -> lookup_extendable(word, file.extendables)
    Error(_) -> option.None
  }
}

fn lookup_extendable(
  word: String,
  extendables: List(ast.Extendable),
) -> Option(String) {
  case list.find(extendables, fn(e) { e.name == word }) {
    Ok(ext) -> {
      let kind = case ext.kind {
        ast.ExtendableRequires -> "Requires"
        ast.ExtendableProvides -> "Provides"
      }
      let fields =
        list.map(ext.body.fields, fn(f) {
          "  - `" <> f.name <> "`: " <> format_value(f.value)
        })
        |> string.join("\n")
      let md =
        "**"
        <> ext.name
        <> "** — "
        <> kind
        <> " extendable"
        <> case fields {
          "" -> ""
          f -> "\n\n**Fields:**\n" <> f
        }
      option.Some(md)
    }
    Error(_) -> option.None
  }
}

fn lookup_type_alias(
  word: String,
  aliases: List(ast.TypeAlias),
) -> Option(String) {
  case list.find(aliases, fn(ta) { ta.name == word }) {
    Ok(ta) -> {
      let resolved = accepted_types.accepted_type_to_string(ta.type_)
      option.Some(
        "**"
        <> ta.name
        <> "** — Type alias\n\nResolves to: `"
        <> resolved
        <> "`",
      )
    }
    Error(_) -> option.None
  }
}

fn format_value(value: ast.Value) -> String {
  case value {
    ast.TypeValue(t) -> accepted_types.accepted_type_to_string(t)
    ast.LiteralValue(lit) -> format_literal(lit)
  }
}

fn format_literal(lit: ast.Literal) -> String {
  case lit {
    ast.LiteralString(s) -> "\"" <> s <> "\""
    ast.LiteralInteger(n) -> string.inspect(n)
    ast.LiteralFloat(f) -> string.inspect(f)
    ast.LiteralTrue -> "true"
    ast.LiteralFalse -> "false"
    ast.LiteralList(_) -> "[...]"
    ast.LiteralStruct(_) -> "{...}"
  }
}

/// Extract the word under the cursor at the given 0-indexed line and character.
fn extract_word_at(content: String, line: Int, character: Int) -> String {
  case line >= 0 {
    False -> ""
    True -> {
      let lines = string.split(content, "\n")
      case list.drop(lines, line) {
        [line_text, ..] -> word_at_column(line_text, character)
        [] -> ""
      }
    }
  }
}

fn word_at_column(line: String, col: Int) -> String {
  let graphemes = string.to_graphemes(line)
  let len = list.length(graphemes)
  // Clamp col to valid range
  let col = case col < 0 {
    True -> 0
    False ->
      case col >= len {
        True -> len - 1
        False -> col
      }
  }
  case len == 0 {
    True -> ""
    False -> {
      // Check if cursor is on a word character
      case list.drop(graphemes, col) {
        [g, ..] ->
          case is_word_char(g) {
            False -> ""
            True -> {
              // Walk left from col to find word start
              let start = find_word_start(graphemes, col)
              // Walk right from col to find word end
              let end = find_word_end(graphemes, col, len)
              graphemes
              |> list.drop(start)
              |> list.take(end - start)
              |> string.join("")
            }
          }
        [] -> ""
      }
    }
  }
}

/// Walk left from col to find the start of the word.
fn find_word_start(graphemes: List(String), col: Int) -> Int {
  find_word_start_loop(graphemes, col, 0, 0)
}

fn find_word_start_loop(
  graphemes: List(String),
  col: Int,
  idx: Int,
  last_non_word: Int,
) -> Int {
  case graphemes {
    [] -> last_non_word
    [g, ..rest] -> {
      case idx > col {
        True -> last_non_word
        False -> {
          let new_last = case is_word_char(g) {
            True -> last_non_word
            False -> idx + 1
          }
          find_word_start_loop(rest, col, idx + 1, new_last)
        }
      }
    }
  }
}

/// Walk right from col to find the end of the word (exclusive).
fn find_word_end(graphemes: List(String), col: Int, len: Int) -> Int {
  find_word_end_loop(graphemes, col, 0, len)
}

fn find_word_end_loop(
  graphemes: List(String),
  col: Int,
  idx: Int,
  len: Int,
) -> Int {
  case graphemes {
    [] -> len
    [g, ..rest] -> {
      case idx > col && !is_word_char(g) {
        True -> idx
        False -> find_word_end_loop(rest, col, idx + 1, len)
      }
    }
  }
}

fn is_word_char(g: String) -> Bool {
  case g {
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z" -> True
    "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F"
    | "G"
    | "H"
    | "I"
    | "J"
    | "K"
    | "L"
    | "M"
    | "N"
    | "O"
    | "P"
    | "Q"
    | "R"
    | "S"
    | "T"
    | "U"
    | "V"
    | "W"
    | "X"
    | "Y"
    | "Z" -> True
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    "_" -> True
    _ -> False
  }
}
