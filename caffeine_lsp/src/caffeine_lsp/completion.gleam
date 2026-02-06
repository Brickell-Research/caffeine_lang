import caffeine_lang/frontend/ast
import caffeine_lang/types.{type TypeMeta}
import caffeine_lsp/file_utils
import caffeine_lsp/keyword_info
import caffeine_lsp/lsp_types.{CikClass, CikField, CikKeyword, CikVariable}
import gleam/bool
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
    ExtendsContext(used) -> extends_completions(content, used)
    TypeContext -> type_completions(content)
    FieldContext(fields) -> field_completions(fields)
    GeneralContext -> general_completions(content)
  }
}

// --- Context detection ---

type CompletionContext {
  ExtendsContext(already_used: List(String))
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
      use <- bool.guard(
        is_extends_context(trimmed),
        ExtendsContext(already_used: extract_used_extends(trimmed)),
      )
      use <- bool.guard(is_type_context(trimmed), TypeContext)
      case get_field_context(content, lines, line) {
        option.Some(fields) -> FieldContext(fields)
        option.None -> GeneralContext
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

/// Extract already-used extendable names from the extends context.
/// e.g. "extends [_base, _auth, " → ["_base", "_auth"]
fn extract_used_extends(before: String) -> List(String) {
  case string.split_once(before, "extends [") {
    Error(_) -> []
    Ok(#(_, after_bracket)) ->
      string.split(after_bracket, ",")
      |> list.map(string.trim)
      |> list.filter(fn(s) { string.starts_with(s, "_") })
  }
}

/// Detect if we're inside a Requires/Provides block and suggest fields
/// from extendables that haven't been defined yet.
fn get_field_context(
  content: String,
  lines: List(String),
  line: Int,
) -> option.Option(List(#(String, String))) {
  case find_enclosing_item(lines, line) {
    option.None -> option.None
    option.Some(item_name) ->
      case file_utils.parse(content) {
        Ok(file_utils.Blueprints(file)) ->
          blueprint_field_context(file, item_name, lines, line)
        Ok(file_utils.Expects(file)) ->
          expects_field_context(file, item_name, lines, line)
        Error(_) -> option.None
      }
  }
}

/// Walk backwards from the cursor line to find the enclosing item name.
fn find_enclosing_item(lines: List(String), line: Int) -> option.Option(String) {
  find_enclosing_item_loop(lines, line)
}

fn find_enclosing_item_loop(
  lines: List(String),
  idx: Int,
) -> option.Option(String) {
  use <- bool.guard(idx < 0, option.None)
  case list.drop(lines, idx) {
    [line_text, ..] -> {
      let trimmed = string.trim(line_text)
      use <- bool.guard(
        string.starts_with(trimmed, "* \""),
        extract_item_name(trimmed),
      )
      find_enclosing_item_loop(lines, idx - 1)
    }
    [] -> option.None
  }
}

/// Extract the item name from a line like `* "my_slo" extends [...]:` or `* "my_slo":`.
fn extract_item_name(trimmed: String) -> option.Option(String) {
  // Drop `* "` prefix
  let after = string.drop_start(trimmed, 3)
  case string.split_once(after, "\"") {
    Ok(#(name, _)) -> option.Some(name)
    Error(_) -> option.None
  }
}

/// Collect available fields from extended extendables for a blueprint item.
fn blueprint_field_context(
  file: ast.BlueprintsFile,
  item_name: String,
  lines: List(String),
  line: Int,
) -> option.Option(List(#(String, String))) {
  let item =
    list.flat_map(file.blocks, fn(b) { b.items })
    |> list.find(fn(i) { i.name == item_name })
  case item {
    Error(_) -> option.None
    Ok(item) -> {
      let extended_fields =
        collect_extended_fields(item.extends, file.extendables)
      let existing = existing_field_names_for_section(lines, line, item)
      let available =
        list.filter(extended_fields, fn(f) { !list.contains(existing, f.0) })
      case available {
        [] -> option.None
        _ -> option.Some(available)
      }
    }
  }
}

/// Collect available fields from extended extendables for an expects item.
fn expects_field_context(
  file: ast.ExpectsFile,
  item_name: String,
  lines: List(String),
  line: Int,
) -> option.Option(List(#(String, String))) {
  let item =
    list.flat_map(file.blocks, fn(b) { b.items })
    |> list.find(fn(i) { i.name == item_name })
  case item {
    Error(_) -> option.None
    Ok(item) -> {
      let extended_fields =
        collect_extended_fields(item.extends, file.extendables)
      let existing = existing_provides_fields(lines, line, item.provides)
      let available =
        list.filter(extended_fields, fn(f) { !list.contains(existing, f.0) })
      case available {
        [] -> option.None
        _ -> option.Some(available)
      }
    }
  }
}

/// Gather field name/detail pairs from all extended extendables.
fn collect_extended_fields(
  extends: List(String),
  extendables: List(ast.Extendable),
) -> List(#(String, String)) {
  list.flat_map(extends, fn(ext_name) {
    case list.find(extendables, fn(e) { e.name == ext_name }) {
      Ok(ext) ->
        list.map(ext.body.fields, fn(f) {
          #(f.name, ast.value_to_string(f.value))
        })
      Error(_) -> []
    }
  })
}

/// Get existing field names based on whether cursor is in Requires or Provides.
fn existing_field_names_for_section(
  lines: List(String),
  line: Int,
  item: ast.BlueprintItem,
) -> List(String) {
  case is_in_requires_section(lines, line) {
    True -> list.map(item.requires.fields, fn(f) { f.name })
    False -> list.map(item.provides.fields, fn(f) { f.name })
  }
}

/// Check if the cursor line is inside a Requires section by walking backwards.
fn is_in_requires_section(lines: List(String), line: Int) -> Bool {
  is_in_requires_loop(lines, line)
}

fn is_in_requires_loop(lines: List(String), idx: Int) -> Bool {
  use <- bool.guard(idx < 0, False)
  case list.drop(lines, idx) {
    [line_text, ..] -> {
      let trimmed = string.trim(line_text)
      use <- bool.guard(string.starts_with(trimmed, "Requires"), True)
      use <- bool.guard(string.starts_with(trimmed, "Provides"), False)
      use <- bool.guard(string.starts_with(trimmed, "* \""), False)
      is_in_requires_loop(lines, idx - 1)
    }
    [] -> False
  }
}

/// Get existing provides field names for expects items.
fn existing_provides_fields(
  _lines: List(String),
  _line: Int,
  provides: ast.Struct,
) -> List(String) {
  list.map(provides.fields, fn(f) { f.name })
}

// --- Completion generators ---

fn extends_completions(
  content: String,
  already_used: List(String),
) -> List(CompletionItem) {
  extendable_items(content)
  |> list.filter(fn(item) { !list.contains(already_used, item.label) })
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
