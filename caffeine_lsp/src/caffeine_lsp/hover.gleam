import caffeine_lang/frontend/ast
import caffeine_lang/types.{type TypeMeta}
import caffeine_lsp/file_utils
import caffeine_lsp/keyword_info
import caffeine_lsp/position_utils
import gleam/int
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

/// Look up user-defined extendables, type aliases, items, and fields.
fn lookup_user_defined(word: String, content: String) -> Option(String) {
  case file_utils.parse(content) {
    Ok(file_utils.Blueprints(file)) ->
      lookup_extendable(word, file.extendables)
      |> option.lazy_or(fn() { lookup_type_alias(word, file.type_aliases) })
      |> option.lazy_or(fn() { lookup_blueprint_item(word, file) })
      |> option.lazy_or(fn() { lookup_blueprint_field(word, file) })
    Ok(file_utils.Expects(file)) ->
      lookup_extendable(word, file.extendables)
      |> option.lazy_or(fn() { lookup_expect_item(word, file) })
      |> option.lazy_or(fn() { lookup_expect_field(word, file) })
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

fn lookup_blueprint_item(
  word: String,
  file: ast.BlueprintsFile,
) -> Option(String) {
  let items = list.flat_map(file.blocks, fn(b) { b.items })
  case list.find(items, fn(i) { i.name == word }) {
    Ok(item) -> {
      let extends_info = case item.extends {
        [] -> ""
        exts -> "\n\nExtends: " <> string.join(exts, ", ")
      }
      let req_count = list.length(item.requires.fields)
      let prov_count = list.length(item.provides.fields)
      option.Some(
        "**"
        <> item.name
        <> "** — Blueprint item"
        <> extends_info
        <> "\n\nRequires: "
        <> int.to_string(req_count)
        <> " fields | Provides: "
        <> int.to_string(prov_count)
        <> " fields",
      )
    }
    Error(_) -> option.None
  }
}

fn lookup_expect_item(word: String, file: ast.ExpectsFile) -> Option(String) {
  let items = list.flat_map(file.blocks, fn(b) { b.items })
  case list.find(items, fn(i) { i.name == word }) {
    Ok(item) -> {
      let extends_info = case item.extends {
        [] -> ""
        exts -> "\n\nExtends: " <> string.join(exts, ", ")
      }
      let prov_count = list.length(item.provides.fields)
      option.Some(
        "**"
        <> item.name
        <> "** — Expectation item"
        <> extends_info
        <> "\n\nProvides: "
        <> int.to_string(prov_count)
        <> " fields",
      )
    }
    Error(_) -> option.None
  }
}

fn lookup_blueprint_field(
  word: String,
  file: ast.BlueprintsFile,
) -> Option(String) {
  let all_fields =
    list.flat_map(file.blocks, fn(b) {
      list.flat_map(b.items, fn(item) {
        list.flatten([item.requires.fields, item.provides.fields])
      })
    })
  lookup_field_in_list(word, all_fields)
}

fn lookup_expect_field(word: String, file: ast.ExpectsFile) -> Option(String) {
  let all_fields =
    list.flat_map(file.blocks, fn(b) {
      list.flat_map(b.items, fn(item) { item.provides.fields })
    })
  lookup_field_in_list(word, all_fields)
}

fn lookup_field_in_list(word: String, fields: List(ast.Field)) -> Option(String) {
  case list.find(fields, fn(f) { f.name == word }) {
    Ok(field) -> {
      let value_str = ast.value_to_string(field.value)
      option.Some(
        "**" <> field.name <> "** — Field\n\nValue: `" <> value_str <> "`",
      )
    }
    Error(_) -> option.None
  }
}
