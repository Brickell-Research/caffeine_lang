import caffeine_lang/frontend/ast
import caffeine_lang/linker/measurements.{
  type Measurement, type MeasurementValidated,
}
import caffeine_lang/types.{type ParsedType, type TypeMeta, ParsedTypeAliasRef}
import caffeine_lsp/file_utils
import caffeine_lsp/keyword_info
import caffeine_lsp/measurement_utils
import caffeine_lsp/position_utils
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// Returns hover markdown text for the word at the given position, or None.
pub fn get_hover(
  content: String,
  line: Int,
  character: Int,
  validated_measurements: List(Measurement(MeasurementValidated)),
) -> Option(String) {
  let word = position_utils.extract_word_at(content, line, character)
  case word {
    "" -> option.None
    w -> lookup_hover(w, content, validated_measurements)
  }
}

/// Look up hover documentation for a token name.
/// Checks built-in types, keywords, then user-defined symbols.
fn lookup_hover(
  word: String,
  content: String,
  validated_measurements: List(Measurement(MeasurementValidated)),
) -> Option(String) {
  case list.find(types.all_type_metas(), fn(m: TypeMeta) { m.name == word }) {
    Ok(meta) -> option.Some(format_type_meta(meta))
    Error(_) ->
      case lookup_keyword(word) {
        option.Some(kw) -> option.Some(kw)
        option.None ->
          lookup_user_defined(word, content, validated_measurements)
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
fn lookup_user_defined(
  word: String,
  content: String,
  validated_measurements: List(Measurement(MeasurementValidated)),
) -> Option(String) {
  case file_utils.parse(content) {
    Ok(file_utils.Measurements(file)) ->
      lookup_extendable(word, file.extendables)
      |> option.lazy_or(fn() { lookup_type_alias(word, file.type_aliases) })
      |> option.lazy_or(fn() { lookup_measurement_item(word, file) })
      |> option.lazy_or(fn() { lookup_measurement_field(word, file) })
    Ok(file_utils.Expects(file)) ->
      lookup_extendable(word, file.extendables)
      |> option.lazy_or(fn() {
        lookup_expect_item(word, file, validated_measurements)
      })
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
      let direct = types.parsed_type_to_string(ta.type_)
      let resolved = resolve_alias_chain(ta.type_, aliases, 0)
      let resolved_str = types.parsed_type_to_string(resolved)
      let display = case direct == resolved_str {
        True -> "`" <> direct <> "`"
        False -> "`" <> direct <> "` → `" <> resolved_str <> "`"
      }
      option.Some(
        "**" <> ta.name <> "** — Type alias\n\nResolves to: " <> display,
      )
    }
    Error(_) -> option.None
  }
}

/// Resolve a type alias chain to its fully concrete type.
/// Guards against cycles with a depth limit (validator catches cycles).
fn resolve_alias_chain(
  type_: ParsedType,
  aliases: List(ast.TypeAlias),
  depth: Int,
) -> ParsedType {
  case depth > 10 {
    True -> type_
    False ->
      case type_ {
        ParsedTypeAliasRef(name) ->
          case list.find(aliases, fn(ta) { ta.name == name }) {
            Ok(ta) -> resolve_alias_chain(ta.type_, aliases, depth + 1)
            Error(_) -> type_
          }
        _ -> type_
      }
  }
}

fn lookup_measurement_item(
  word: String,
  file: ast.MeasurementsFile(ast.Parsed),
) -> Option(String) {
  let items = file.items
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
        <> "** — Measurement item"
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

fn lookup_expect_item(
  word: String,
  file: ast.ExpectsFile(ast.Parsed),
  validated_measurements: List(Measurement(MeasurementValidated)),
) -> Option(String) {
  // Find the item and its enclosing block (for measurement ref lookup).
  let found =
    list.find_map(file.blocks, fn(block) {
      case list.find(block.items, fn(i) { i.name == word }) {
        Ok(item) -> Ok(#(item, block.measurement))
        Error(_) -> Error(Nil)
      }
    })
  case found {
    Ok(#(item, measurement_ref)) -> {
      let extends_info = case item.extends {
        [] -> ""
        exts -> "\n\nExtends: " <> string.join(exts, ", ")
      }
      let prov_count = list.length(item.provides.fields)
      let requires_info = case measurement_ref {
        option.Some(ref) ->
          format_measurement_requires(ref, validated_measurements)
        option.None -> ""
      }
      option.Some(
        "**"
        <> item.name
        <> "** — Expectation item"
        <> extends_info
        <> "\n\nProvides: "
        <> int.to_string(prov_count)
        <> " fields"
        <> requires_info,
      )
    }
    Error(_) -> option.None
  }
}

/// Format the measurement's remaining Requires params for hover display.
fn format_measurement_requires(
  measurement_ref: String,
  validated_measurements: List(Measurement(MeasurementValidated)),
) -> String {
  case list.find(validated_measurements, fn(b) { b.name == measurement_ref }) {
    Error(_) -> ""
    Ok(measurement) -> {
      let remaining = measurement_utils.compute_remaining_params(measurement)
      let params =
        dict.to_list(remaining)
        |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
        |> list.map(fn(pair) {
          "  - `" <> pair.0 <> "`: " <> types.accepted_type_to_string(pair.1)
        })
      case params {
        [] -> ""
        _ -> "\n\n**Measurement Requires:**\n" <> string.join(params, "\n")
      }
    }
  }
}

fn lookup_measurement_field(
  word: String,
  file: ast.MeasurementsFile(ast.Parsed),
) -> Option(String) {
  let all_fields =
    list.flat_map(file.items, fn(item) {
      list.flatten([item.requires.fields, item.provides.fields])
    })
  lookup_field_in_list(word, all_fields)
}

fn lookup_expect_field(
  word: String,
  file: ast.ExpectsFile(ast.Parsed),
) -> Option(String) {
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
