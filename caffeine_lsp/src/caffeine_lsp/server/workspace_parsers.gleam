/// Stateless parsing utilities for extracting blueprint names, expectation
/// identifiers, and locating items within Caffeine file text.
import gleam/bool
import gleam/dict.{type Dict}
import gleam/list
import gleam/set.{type Set}
import gleam/string

/// Extract blueprint item names from a file's text.
/// Returns an empty list for non-blueprint files.
@internal
pub fn extract_blueprint_names(text: String) -> List(String) {
  use <- bool.guard(!string.contains(text, "Blueprints for"), [])
  text
  |> string.split("\n")
  |> list.filter(fn(line) { !is_comment_line(line) })
  |> list.filter_map(extract_item_name)
}

/// Extract blueprint names referenced via `Expectations for "name"` headers.
@internal
pub fn extract_referenced_blueprint_names(text: String) -> List(String) {
  text
  |> string.split("\n")
  |> list.filter(fn(line) { !is_comment_line(line) })
  |> list.filter_map(fn(line) {
    let trimmed = string.trim_start(line)
    use <- bool.guard(!string.starts_with(trimmed, "Expectations"), Error(Nil))
    // Look for: Expectations for "name"
    case string.split(trimmed, "\"") {
      [_, name, ..] -> Ok(name)
      _ -> Error(Nil)
    }
  })
}

/// Extract org/team/service from a file path (last 3 path segments).
@internal
pub fn extract_path_prefix(file_path: String) -> #(String, String, String) {
  let segments = string.split(file_path, "/")
  let len = list.length(segments)
  case len >= 3 {
    False -> #("unknown", "unknown", "unknown")
    True -> {
      let last3 = list.drop(segments, len - 3)
      case last3 {
        [org, team, service_file] -> {
          let service =
            service_file
            |> string.replace(".caffeine", "")
            |> string.replace(".json", "")
          #(org, team, service)
        }
        _ -> #("unknown", "unknown", "unknown")
      }
    }
  }
}

/// Extract expectation identifiers (org.team.service.name) from an expects file.
/// The uri should be a file:// URI.
@internal
pub fn extract_expectation_identifiers(
  text: String,
  uri: String,
) -> Dict(String, String) {
  use <- bool.guard(!string.contains(text, "Expectations for"), dict.new())
  let file_path = case string.starts_with(uri, "file://") {
    True -> string.drop_start(uri, 7)
    False -> uri
  }
  let #(org, team, service) = extract_path_prefix(file_path)
  let prefix = org <> "." <> team <> "." <> service <> "."
  text
  |> string.split("\n")
  |> list.filter(fn(line) { !is_comment_line(line) })
  |> list.filter_map(fn(line) {
    case extract_item_name(line) {
      Ok(name) -> Ok(#(name, prefix <> name))
      Error(Nil) -> Error(Nil)
    }
  })
  |> dict.from_list
}

/// Find the location of a blueprint item (`* "name"`) within file text.
/// Returns `#(line, col, name_len)` or Error.
@internal
pub fn find_blueprint_item_location(
  text: String,
  item_name: String,
) -> Result(#(Int, Int, Int), Nil) {
  let needle = "\"" <> item_name <> "\""
  text
  |> string.split("\n")
  |> find_item_loop(needle, item_name, 0)
}

fn find_item_loop(
  lines: List(String),
  needle: String,
  item_name: String,
  line_num: Int,
) -> Result(#(Int, Int, Int), Nil) {
  case lines {
    [] -> Error(Nil)
    [line, ..rest] -> {
      case is_item_line(line) {
        False -> find_item_loop(rest, needle, item_name, line_num + 1)
        True -> {
          case find_substring_index(line, needle) {
            Error(Nil) -> find_item_loop(rest, needle, item_name, line_num + 1)
            Ok(idx) -> Ok(#(line_num, idx + 1, string.length(item_name)))
          }
        }
      }
    }
  }
}

/// Check if a line looks like an item definition: `* "`.
fn is_item_line(line: String) -> Bool {
  let trimmed = string.trim_start(line)
  string.starts_with(trimmed, "* \"")
}

/// Extract the item name from a line like `  * "MyItem"`.
fn extract_item_name(line: String) -> Result(String, Nil) {
  let trimmed = string.trim_start(line)
  use <- bool.guard(!string.starts_with(trimmed, "* \""), Error(Nil))
  // After `* "`, extract up to the closing quote.
  let after_star = string.drop_start(trimmed, 3)
  case string.split(after_star, "\"") {
    [name, ..] if name != "" -> Ok(name)
    _ -> Error(Nil)
  }
}

/// Find the index of a substring within a string.
fn find_substring_index(haystack: String, needle: String) -> Result(Int, Nil) {
  use <- bool.guard(!string.contains(haystack, needle), Error(Nil))
  let parts = string.split(haystack, needle)
  case parts {
    [before, ..] -> Ok(string.length(before))
    _ -> Error(Nil)
  }
}

/// Update blueprint and expectation indices for a file.
/// Returns `#(updated_bp_index, updated_exp_index, changed)`.
@internal
pub fn apply_index_updates(
  uri: String,
  text: String,
  blueprint_index: Dict(String, Set(String)),
  expectation_index: Dict(String, Dict(String, String)),
) -> #(Dict(String, Set(String)), Dict(String, Dict(String, String)), Bool) {
  let new_names = extract_blueprint_names(text)
  let new_names_set = set.from_list(new_names)
  let old_names = dict.get(blueprint_index, uri)

  let names_changed = case old_names {
    Error(_) -> !list.is_empty(new_names)
    Ok(old_set) -> old_set != new_names_set
  }

  let bp_index = case list.is_empty(new_names) {
    True -> dict.delete(blueprint_index, uri)
    False -> dict.insert(blueprint_index, uri, new_names_set)
  }

  let new_ids = extract_expectation_identifiers(text, uri)
  let old_ids = dict.get(expectation_index, uri)

  let ids_changed = case old_ids {
    Error(_) -> !dict.is_empty(new_ids)
    Ok(old_map) -> old_map != new_ids
  }

  let exp_index = case dict.is_empty(new_ids) {
    True -> dict.delete(expectation_index, uri)
    False -> dict.insert(expectation_index, uri, new_ids)
  }

  #(bp_index, exp_index, names_changed || ids_changed)
}

fn is_comment_line(line: String) -> Bool {
  string.starts_with(string.trim_start(line), "#")
}
