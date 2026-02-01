import caffeine_lang/frontend/ast
import caffeine_lang/type_info.{type TypeMeta}
import caffeine_lang/types
import caffeine_lsp/file_utils
import caffeine_lsp/keyword_info
import gleam/json
import gleam/list
import gleam/option
import gleam/string

// LSP CompletionItemKind constants
const kind_keyword = 14

const kind_class = 7

const kind_variable = 6

const kind_field = 5

/// Returns a list of completion item JSON objects, context-aware based on
/// the cursor position in the document.
pub fn get_completions(
  content: String,
  line: Int,
  character: Int,
) -> List(json.Json) {
  let context = get_context(content, line, character)
  case context {
    ExtendsContext -> extends_completions(content)
    TypeContext -> type_completions(content)
    FieldContext(fields) -> field_completions(fields)
    GeneralContext -> general_completions(content)
  }
}

// --- Context detection ---

type CompletionContext {
  ExtendsContext
  TypeContext
  FieldContext(available_fields: List(#(String, String)))
  GeneralContext
}

fn get_context(content: String, line: Int, character: Int) -> CompletionContext {
  let lines = string.split(content, "\n")
  case list.drop(lines, line) {
    [line_text, ..] -> {
      let before_cursor = string.slice(line_text, 0, character)
      let trimmed = string.trim(before_cursor)
      case is_extends_context(trimmed) {
        True -> ExtendsContext
        False ->
          case is_type_context(trimmed) {
            True -> TypeContext
            False ->
              case get_field_context(content, lines, line) {
                option.Some(fields) -> FieldContext(fields)
                option.None -> GeneralContext
              }
          }
      }
    }
    [] -> GeneralContext
  }
}

fn is_extends_context(before: String) -> Bool {
  // After "extends [" or "extends [_foo, "
  string.contains(before, "extends [")
}

fn is_type_context(before: String) -> Bool {
  // After a colon (field type position) or after a type keyword like "List("
  string.ends_with(string.trim(before), ":") || string.ends_with(before, "(")
}

/// Detect if we're inside a Requires/Provides block and suggest fields
/// from extendables that haven't been defined yet.
fn get_field_context(
  content: String,
  _lines: List(String),
  _line: Int,
) -> option.Option(List(#(String, String))) {
  // For now, return None — field completion requires deeper context analysis
  // that would need tracking which block we're in and what extends are used
  case content {
    _ -> option.None
  }
}

// --- Completion generators ---

fn extends_completions(content: String) -> List(json.Json) {
  // Suggest extendable names from the current file
  let file_items = case file_utils.parse(content) {
    Ok(file_utils.Blueprints(file)) ->
      list.map(file.extendables, fn(e) {
        let detail = ast.extendable_kind_to_string(e.kind) <> " extendable"
        completion_item(e.name, kind_variable, detail)
      })
    Ok(file_utils.Expects(file)) ->
      list.map(file.extendables, fn(e) {
        let detail = ast.extendable_kind_to_string(e.kind) <> " extendable"
        completion_item(e.name, kind_variable, detail)
      })
    Error(_) -> []
  }
  file_items
}

fn type_completions(content: String) -> List(json.Json) {
  let type_items =
    types.all_type_metas()
    |> list.map(fn(m: TypeMeta) {
      completion_item(m.name, kind_class, m.description)
    })

  // Also add type aliases from the file
  let alias_items = case file_utils.parse(content) {
    Ok(file_utils.Blueprints(file)) ->
      list.map(file.type_aliases, fn(ta) {
        let detail = "Type alias → " <> types.parsed_type_to_string(ta.type_)
        completion_item(ta.name, kind_variable, detail)
      })
    _ -> []
  }

  list.flatten([type_items, alias_items])
}

fn field_completions(fields: List(#(String, String))) -> List(json.Json) {
  list.map(fields, fn(f) { completion_item(f.0, kind_field, f.1) })
}

fn general_completions(content: String) -> List(json.Json) {
  let kw_items = keyword_items()
  let type_items =
    types.all_type_metas()
    |> list.map(fn(m: TypeMeta) {
      completion_item(m.name, kind_class, m.description)
    })

  // Add extendable and type alias names from file
  let file_items = case file_utils.parse(content) {
    Ok(file_utils.Blueprints(file)) -> {
      let ext_items =
        list.map(file.extendables, fn(e) {
          let detail = ast.extendable_kind_to_string(e.kind) <> " extendable"
          completion_item(e.name, kind_variable, detail)
        })
      let alias_items =
        list.map(file.type_aliases, fn(ta) {
          let detail = "Type alias → " <> types.parsed_type_to_string(ta.type_)
          completion_item(ta.name, kind_variable, detail)
        })
      list.flatten([ext_items, alias_items])
    }
    Ok(file_utils.Expects(file)) ->
      list.map(file.extendables, fn(e) {
        let detail = ast.extendable_kind_to_string(e.kind) <> " extendable"
        completion_item(e.name, kind_variable, detail)
      })
    Error(_) -> []
  }

  list.flatten([kw_items, type_items, file_items])
}

// --- Helpers ---

fn keyword_items() -> List(json.Json) {
  keyword_info.all_keywords()
  |> list.map(fn(kw) { completion_item(kw.name, kind_keyword, kw.description) })
}

fn completion_item(label: String, kind: Int, detail: String) -> json.Json {
  json.object([
    #("label", json.string(label)),
    #("kind", json.int(kind)),
    #("detail", json.string(detail)),
  ])
}
