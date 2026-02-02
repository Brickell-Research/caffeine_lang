import caffeine_lang/frontend/ast
import caffeine_lang/types.{type TypeMeta}
import caffeine_lsp/file_utils
import caffeine_lsp/keyword_info
import caffeine_lsp/position_utils
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// Returns hover markdown text for the word at the given position, or None.
pub fn get_hover(content: String, line: Int, character: Int) -> Option(String) {
  let word = position_utils.extract_word_at(content, line, character)
  case word {
    "" -> option.None
    w -> lookup_hover(w, content)
  }
}

/// Look up hover documentation for a token name.
/// Checks built-in types, keywords, then user-defined symbols.
fn lookup_hover(word: String, content: String) -> Option(String) {
  case list.find(types.all_type_metas(), fn(m: TypeMeta) { m.name == word }) {
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
      let kind = ast.extendable_kind_to_string(ext.kind)
      let fields =
        list.map(ext.body.fields, fn(f) {
          "  - `" <> f.name <> "`: " <> ast.value_to_string(f.value)
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
      let resolved = types.parsed_type_to_string(ta.type_)
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
