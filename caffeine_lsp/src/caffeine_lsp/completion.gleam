import caffeine_lang/frontend/ast
import caffeine_lang/linker/measurements.{
  type Measurement, type MeasurementValidated,
}
import caffeine_lang/types.{type TypeMeta}
import caffeine_lsp/file_utils
import caffeine_lsp/keyword_info
import caffeine_lsp/lsp_types.{
  CikClass, CikField, CikKeyword, CikModule, CikVariable,
}
import caffeine_lsp/measurement_utils
import gleam/bool
import gleam/dict
import gleam/list
import gleam/option.{type Option}
import gleam/set
import gleam/string

/// A completion item returned to the editor.
pub type CompletionItem {
  CompletionItem(
    label: String,
    kind: Int,
    detail: String,
    insert_text: Option(String),
    insert_text_format: Option(Int),
  )
}

/// Returns a list of completion items, context-aware based on
/// the cursor position in the document. Workspace measurement names
/// from other files are used for cross-file measurement header completion.
/// Validated measurements enable field suggestions from measurement Requires.
pub fn get_completions(
  content: String,
  line: Int,
  character: Int,
  workspace_measurement_names: List(String),
  validated_measurements: List(Measurement(MeasurementValidated)),
) -> List(CompletionItem) {
  // Parse once and reuse across all completion paths.
  let parsed = file_utils.parse(content)
  let context =
    get_context(content, parsed, line, character, validated_measurements)
  case context {
    MeasurementHeaderContext(prefix) ->
      measurement_header_completions(workspace_measurement_names, prefix)
    ExtendsContext(used) -> extends_completions(content, parsed, used)
    TypeContext -> type_completions(parsed)
    FieldContext(fields) -> field_completions(fields)
    GeneralContext -> general_completions(parsed)
  }
}

// --- Context detection ---

type CompletionContext {
  MeasurementHeaderContext(prefix: String)
  ExtendsContext(already_used: List(String))
  TypeContext
  FieldContext(available_fields: List(#(String, String)))
  GeneralContext
}

fn get_context(
  content: String,
  parsed: Result(file_utils.ParsedFile, a),
  line: Int,
  character: Int,
  validated_measurements: List(Measurement(MeasurementValidated)),
) -> CompletionContext {
  let lines = string.split(content, "\n")
  case list.drop(lines, line) {
    [line_text, ..] -> {
      let before_cursor = string.slice(line_text, 0, character)
      let trimmed = string.trim(before_cursor)
      case get_measurement_header_prefix(trimmed) {
        option.Some(prefix) -> MeasurementHeaderContext(prefix)
        option.None -> {
          use <- bool.guard(
            is_extends_context(trimmed),
            ExtendsContext(already_used: extract_used_extends(trimmed)),
          )
          use <- bool.guard(is_type_context(trimmed), TypeContext)
          case get_field_context(parsed, lines, line, validated_measurements) {
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

/// Detect if cursor is inside a measurement header reference, e.g.
/// `Expectations measured by "api` → Some("api"), `Expectations measured by "` → Some("").
fn get_measurement_header_prefix(before: String) -> option.Option(String) {
  case string.split_once(before, "Expectations measured by \"") {
    Ok(#(_, after_quote)) ->
      // Only match if the closing quote hasn't been typed yet
      case string.contains(after_quote, "\"") {
        True -> option.None
        False -> option.Some(after_quote)
      }
    Error(_) -> option.None
  }
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
  parsed: Result(file_utils.ParsedFile, a),
  lines: List(String),
  line: Int,
  validated_measurements: List(Measurement(MeasurementValidated)),
) -> option.Option(List(#(String, String))) {
  case find_enclosing_item(lines, line) {
    option.None -> option.None
    option.Some(item_name) ->
      case parsed {
        Ok(file_utils.Measurements(file)) ->
          measurement_field_context(file, item_name, lines, line)
        Ok(file_utils.Expects(file)) ->
          expects_field_context(
            file,
            item_name,
            lines,
            line,
            validated_measurements,
          )
        Error(_) -> option.None
      }
  }
}

/// Walk backwards from the cursor line to find the enclosing item name.
@internal
pub fn find_enclosing_item(
  lines: List(String),
  line: Int,
) -> option.Option(String) {
  // Take lines up to and including the cursor line, then reverse to walk backwards.
  let prefix = list.take(lines, line + 1) |> list.reverse
  find_enclosing_item_loop(prefix)
}

fn find_enclosing_item_loop(lines: List(String)) -> option.Option(String) {
  case lines {
    [] -> option.None
    [line_text, ..rest] -> {
      let trimmed = string.trim(line_text)
      case is_item_line(line_text, trimmed) {
        True -> extract_item_name(trimmed)
        False -> find_enclosing_item_loop(rest)
      }
    }
  }
}

/// Walk backwards from the cursor line to find the enclosing
/// `Expectations measured by "name"` header and return the measurement ref.
@internal
pub fn find_enclosing_measurement_ref(
  lines: List(String),
  line: Int,
) -> option.Option(String) {
  let prefix = list.take(lines, line + 1) |> list.reverse
  find_enclosing_measurement_ref_loop(prefix)
}

fn find_enclosing_measurement_ref_loop(
  lines: List(String),
) -> option.Option(String) {
  case lines {
    [] -> option.None
    [line_text, ..rest] -> {
      let trimmed = string.trim(line_text)
      case string.split_once(trimmed, "Expectations measured by \"") {
        Ok(#(_, after)) ->
          case string.split_once(after, "\"") {
            Ok(#(name, _)) -> option.Some(name)
            Error(_) -> option.None
          }
        Error(_) -> find_enclosing_measurement_ref_loop(rest)
      }
    }
  }
}

/// Extract the item name from an item line. Handles both measurement items
/// (`"name":`) and expect items (`* "name":`).
fn extract_item_name(trimmed: String) -> option.Option(String) {
  case string.starts_with(trimmed, "* \"") {
    // Expect item: drop `* "` prefix (3 chars)
    True -> {
      let after = string.drop_start(trimmed, 3)
      case string.split_once(after, "\"") {
        Ok(#(name, _)) -> option.Some(name)
        Error(_) -> option.None
      }
    }
    // Measurement item: drop `"` prefix (1 char)
    False -> {
      let after = string.drop_start(trimmed, 1)
      case string.split_once(after, "\"") {
        Ok(#(name, _)) -> option.Some(name)
        Error(_) -> option.None
      }
    }
  }
}

/// Collect available fields from extended extendables for a measurement item.
fn measurement_field_context(
  file: ast.MeasurementsFile(ast.Parsed),
  item_name: String,
  lines: List(String),
  line: Int,
) -> option.Option(List(#(String, String))) {
  let item =
    file.items
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

/// Collect available fields from extended extendables and measurement
/// remaining params for an expects item.
fn expects_field_context(
  file: ast.ExpectsFile(ast.Parsed),
  item_name: String,
  lines: List(String),
  line: Int,
  validated_measurements: List(Measurement(MeasurementValidated)),
) -> option.Option(List(#(String, String))) {
  let item =
    list.flat_map(file.blocks, fn(b) { b.items })
    |> list.find(fn(i) { i.name == item_name })
  case item {
    Error(_) -> option.None
    Ok(item) -> {
      let extended_fields =
        collect_extended_fields(item.extends, file.extendables)
      let existing = existing_provides_fields(item.provides)
      let existing_set = set.from_list(existing)

      // Add fields from the measurement's Requires (remaining params).
      let measurement_fields =
        measurement_remaining_fields(lines, line, validated_measurements)
      let extended_names = list.map(extended_fields, fn(f) { f.0 })
      let extended_set = set.from_list(extended_names)

      // Merge: extendable fields + measurement params not already in extendables
      let merged =
        list.append(
          extended_fields,
          list.filter(measurement_fields, fn(f) {
            !set.contains(extended_set, f.0)
          }),
        )
      let available =
        list.filter(merged, fn(f) { !set.contains(existing_set, f.0) })
      case available {
        [] -> option.None
        _ -> option.Some(available)
      }
    }
  }
}

/// Look up the measurement's remaining params and return as field name/type pairs.
fn measurement_remaining_fields(
  lines: List(String),
  line: Int,
  validated_measurements: List(Measurement(MeasurementValidated)),
) -> List(#(String, String)) {
  case find_enclosing_measurement_ref(lines, line) {
    option.None -> []
    option.Some(measurement_ref) ->
      case
        list.find(validated_measurements, fn(b) { b.name == measurement_ref })
      {
        Error(_) -> []
        Ok(measurement) ->
          measurement_utils.compute_remaining_params(measurement)
          |> dict.to_list
          |> list.map(fn(pair) {
            #(pair.0, types.accepted_type_to_string(pair.1))
          })
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
  item: ast.MeasurementItem,
) -> List(String) {
  case is_in_requires_section(lines, line) {
    True -> list.map(item.requires.fields, fn(f) { f.name })
    False -> list.map(item.provides.fields, fn(f) { f.name })
  }
}

/// Check if the cursor line is inside a Requires section by walking backwards.
fn is_in_requires_section(lines: List(String), line: Int) -> Bool {
  // Take lines up to and including the cursor line, then reverse to walk backwards.
  let prefix = list.take(lines, line + 1) |> list.reverse
  is_in_requires_loop(prefix)
}

fn is_in_requires_loop(lines: List(String)) -> Bool {
  case lines {
    [] -> False
    [line_text, ..rest] -> {
      let trimmed = string.trim(line_text)
      use <- bool.guard(string.starts_with(trimmed, "Requires"), True)
      use <- bool.guard(string.starts_with(trimmed, "Provides"), False)
      use <- bool.guard(is_item_line(line_text, trimmed), False)
      is_in_requires_loop(rest)
    }
  }
}

/// Check whether a line is an item header. Matches both measurement items
/// (`"name":` at column 0) and expect items (`* "name":` indented).
/// Uses the raw line to check indent so quoted field names at deeper
/// indentation are not mistaken for items.
fn is_item_line(raw_line: String, trimmed: String) -> Bool {
  // Expect items: `* "name"` at any indent
  string.starts_with(trimmed, "* \"")
  // Measurement items: `"name"` at column 0 (no indentation)
  || string.starts_with(raw_line, "\"")
}

/// Get existing provides field names for expects items.
fn existing_provides_fields(provides: ast.Struct) -> List(String) {
  list.map(provides.fields, fn(f) { f.name })
}

// --- Completion generators ---

/// Suggest measurement names from the workspace, filtered by the typed prefix.
fn measurement_header_completions(
  workspace_measurement_names: List(String),
  prefix: String,
) -> List(CompletionItem) {
  workspace_measurement_names
  |> list.filter(fn(name) { string.starts_with(name, prefix) })
  |> list.map(fn(name) {
    CompletionItem(
      name,
      lsp_types.completion_item_kind_to_int(CikModule),
      "Measurement",
      option.None,
      option.None,
    )
  })
}

fn extends_completions(
  content: String,
  parsed: Result(file_utils.ParsedFile, a),
  already_used: List(String),
) -> List(CompletionItem) {
  extendable_items(content, parsed)
  |> list.filter(fn(item) { !list.contains(already_used, item.label) })
}

fn type_completions(
  parsed: Result(file_utils.ParsedFile, a),
) -> List(CompletionItem) {
  let type_items = type_meta_items()

  // Also add type aliases from the file
  let alias_items = case parsed {
    Ok(file_utils.Measurements(file)) -> type_alias_items(file.type_aliases)
    _ -> []
  }

  list.flatten([type_items, alias_items])
}

fn field_completions(fields: List(#(String, String))) -> List(CompletionItem) {
  list.map(fields, fn(f) {
    CompletionItem(
      f.0,
      lsp_types.completion_item_kind_to_int(CikField),
      f.1,
      option.Some(f.0 <> ": $1"),
      option.Some(2),
    )
  })
}

fn general_completions(
  parsed: Result(file_utils.ParsedFile, a),
) -> List(CompletionItem) {
  let kw_items = keyword_items()
  let t_items = type_meta_items()

  // Add extendable and type alias names from file
  let file_items = case parsed {
    Ok(file_utils.Measurements(file)) ->
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
      option.None,
      option.None,
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
      option.None,
      option.None,
    )
  })
}

/// Get extendable completion items. Falls back to text-based extraction
/// when the file cannot be parsed (e.g. user is mid-edit).
fn extendable_items(
  content: String,
  parsed: Result(file_utils.ParsedFile, a),
) -> List(CompletionItem) {
  case parsed {
    Ok(file_utils.Measurements(file)) ->
      extendable_items_from_list(file.extendables)
    Ok(file_utils.Expects(file)) -> extendable_items_from_list(file.extendables)
    Error(_) -> extract_extendable_names_from_text(content)
  }
}

/// Extract extendable names from raw text when parsing fails.
/// Scans for lines matching `_name (Provides|Requires):` at indent 0.
fn extract_extendable_names_from_text(content: String) -> List(CompletionItem) {
  string.split(content, "\n")
  |> list.filter_map(fn(line) {
    let trimmed = string.trim_start(line)
    let indent = string.length(line) - string.length(trimmed)
    case indent == 0 && string.starts_with(trimmed, "_") {
      False -> Error(Nil)
      True ->
        case string.split_once(trimmed, " (") {
          Error(_) -> Error(Nil)
          Ok(#(name, rest)) ->
            case
              string.starts_with(rest, "Provides)")
              || string.starts_with(rest, "Requires)")
            {
              False -> Error(Nil)
              True ->
                Ok(CompletionItem(
                  name,
                  lsp_types.completion_item_kind_to_int(CikVariable),
                  "extendable",
                  option.None,
                  option.None,
                ))
            }
        }
    }
  })
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
      option.None,
      option.None,
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
      option.None,
      option.None,
    )
  })
}
