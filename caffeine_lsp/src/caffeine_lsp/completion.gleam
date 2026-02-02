import caffeine_lang/frontend/ast
import caffeine_lang/types.{type TypeMeta}
import caffeine_lsp/file_utils
import caffeine_lsp/keyword_info
import caffeine_lsp/lsp_types.{CikClass, CikField, CikKeyword, CikVariable}
import gleam/list
import gleam/option
import gleam/string

/// A completion item returned to the editor.
pub type CompletionItem {
  CompletionItem(label: String, kind: Int, detail: String)
}

/// Returns a list of completion items, context-aware based on
/// the cursor position in the document.
pub fn get_completions(
  content: String,
  line: Int,
  character: Int,
) -> List(CompletionItem) {
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

fn extends_completions(content: String) -> List(CompletionItem) {
  extendable_items(content)
}

fn type_completions(content: String) -> List(CompletionItem) {
  let type_items = type_meta_items()

  // Also add type aliases from the file
  let alias_items = case file_utils.parse(content) {
    Ok(file_utils.Blueprints(file)) -> type_alias_items(file.type_aliases)
    _ -> []
  }

  list.flatten([type_items, alias_items])
}

fn field_completions(fields: List(#(String, String))) -> List(CompletionItem) {
  list.map(fields, fn(f) {
    CompletionItem(f.0, lsp_types.completion_item_kind_to_int(CikField), f.1)
  })
}

fn general_completions(content: String) -> List(CompletionItem) {
  let kw_items = keyword_items()
  let t_items = type_meta_items()

  // Add extendable and type alias names from file
  let file_items = case file_utils.parse(content) {
    Ok(file_utils.Blueprints(file)) ->
      list.flatten([
        extendable_items_from_list(file.extendables),
        type_alias_items(file.type_aliases),
      ])
    Ok(file_utils.Expects(file)) -> extendable_items_from_list(file.extendables)
    Error(_) -> []
  }

  list.flatten([kw_items, t_items, file_items])
}

// --- Shared item builders ---

fn keyword_items() -> List(CompletionItem) {
  keyword_info.all_keywords()
  |> list.map(fn(kw) {
    CompletionItem(
      kw.name,
      lsp_types.completion_item_kind_to_int(CikKeyword),
      kw.description,
    )
  })
}

fn type_meta_items() -> List(CompletionItem) {
  // Use completable_type_metas to exclude refinement types (OneOf,
  // InclusiveRange) which are not standalone types a user would complete.
  types.completable_type_metas()
  |> list.map(fn(m: TypeMeta) {
    CompletionItem(
      m.name,
      lsp_types.completion_item_kind_to_int(CikClass),
      m.description,
    )
  })
}

fn extendable_items(content: String) -> List(CompletionItem) {
  case file_utils.parse(content) {
    Ok(file_utils.Blueprints(file)) ->
      extendable_items_from_list(file.extendables)
    Ok(file_utils.Expects(file)) -> extendable_items_from_list(file.extendables)
    Error(_) -> []
  }
}

fn extendable_items_from_list(
  extendables: List(ast.Extendable),
) -> List(CompletionItem) {
  list.map(extendables, fn(e) {
    let detail = ast.extendable_kind_to_string(e.kind) <> " extendable"
    CompletionItem(
      e.name,
      lsp_types.completion_item_kind_to_int(CikVariable),
      detail,
    )
  })
}

fn type_alias_items(aliases: List(ast.TypeAlias)) -> List(CompletionItem) {
  list.map(aliases, fn(ta) {
    let detail = "Type alias → " <> types.parsed_type_to_string(ta.type_)
    CompletionItem(
      ta.name,
      lsp_types.completion_item_kind_to_int(CikVariable),
      detail,
    )
  })
}
