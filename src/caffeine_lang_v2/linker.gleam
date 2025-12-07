import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/middle_end.{type IntermediateRepresentation}
import caffeine_lang_v2/parser/artifacts
import caffeine_lang_v2/parser/blueprints
import caffeine_lang_v2/parser/expectations
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub type LinkerError {
  ParseError(msg: String)
  SemanticError(msg: String)
}

pub fn standard_library_directory() -> String {
  "src/caffeine_lang_v2/standard_library"
}

/// Link will fetch, then parse all configuration files, combining them into one single
/// abstract syntax tree (AST) object. In the future how we fetch these files will
/// change to enable fetching from remote locations, via git, etc. but for now we
/// just support standard library artifacts, a single blueprint file, and a single
/// expectations directory. Furthermore note that we will ignore non-json files within
/// an org's team's expectation directory and incorrectly placed json files will also
/// be ignored.
pub fn link(
  blueprint_file_path: String,
  expectations_directory: String,
) -> Result(List(IntermediateRepresentation), LinkerError) {
  use artifacts <- result_try(fetch_artifacts())
  use blueprints <- result_try(fetch_blueprints(blueprint_file_path, artifacts))
  use irs <- result_try(fetch_expectations(expectations_directory, blueprints))

  // Apply semantic analysis / middle-end transformations
  use analyzed_irs <- result_try(
    middle_end.execute(irs)
    |> result.map_error(format_semantic_error),
  )

  Ok(analyzed_irs)
}

fn fetch_artifacts() -> Result(List(artifacts.Artifact), LinkerError) {
  artifacts.parse_from_file(standard_library_directory() <> "/artifacts.json")
  |> result.map_error(format_parse_error)
}

fn fetch_blueprints(
  blueprint_file_path: String,
  artifacts: List(artifacts.Artifact),
) -> Result(List(blueprints.Blueprint), LinkerError) {
  blueprints.parse_from_file(blueprint_file_path, artifacts)
  |> result.map_error(format_parse_error)
}

fn fetch_expectations(
  expectations_directory: String,
  blueprints: List(blueprints.Blueprint),
) -> Result(List(IntermediateRepresentation), LinkerError) {
  use expectations_files <- result_try(
    get_instantiation_json_files(expectations_directory)
    |> result.map_error(ParseError),
  )

  case expectations_files {
    [] ->
      Error(ParseError(
        "No expectation files found in: " <> expectations_directory,
      ))
    _ ->
      expectations_files
      |> list.map(fn(file_path) {
        expectations.parse_from_file(file_path, blueprints)
        |> result.map_error(format_parse_error)
      })
      |> result.all()
      |> result.map(list.flatten)
  }
}

fn format_parse_error(error: helpers.ParseError) -> LinkerError {
  case error {
    helpers.FileReadError(msg) -> ParseError("File read error: " <> msg)
    helpers.JsonParserError(msg) -> ParseError("JSON parse error: " <> msg)
    helpers.DuplicateError(msg) -> ParseError("Duplicate error: " <> msg)
  }
}

fn format_semantic_error(error: middle_end.SemanticError) -> LinkerError {
  case error {
    middle_end.QueryResolutionError(msg) -> SemanticError(msg)
  }
}

fn result_try(result: Result(a, e), next: fn(a) -> Result(b, e)) -> Result(b, e) {
  case result {
    Ok(value) -> next(value)
    Error(err) -> Error(err)
  }
}

// ==== Private ====
fn read_directory_or_error(
  directory_path: String,
) -> Result(List(String), String) {
  case simplifile.read_directory(directory_path) {
    Ok(items) -> Ok(items)
    Error(_) -> Error("Failed to read directory: " <> directory_path)
  }
}

fn process_top_level_item(
  base_directory: String,
  item_name: String,
  accumulated_files: List(String),
) -> Result(List(String), String) {
  let item_path = base_directory <> "/" <> item_name

  case is_directory(item_path) {
    True -> collect_json_files_from_subdirectory(item_path, accumulated_files)
    False -> Ok(accumulated_files)
    // Skip files at the top level
  }
}

fn is_directory(path: String) -> Bool {
  case simplifile.is_directory(path) {
    Ok(True) -> True
    _ -> False
  }
}

fn collect_json_files_from_subdirectory(
  subdirectory_path: String,
  accumulated_files: List(String),
) -> Result(List(String), String) {
  use items_in_subdirectory <- result.try(read_directory_or_error(
    subdirectory_path,
  ))

  // Go one level deeper - iterate over nested directories and collect JSON files from each
  items_in_subdirectory
  |> list.try_fold(accumulated_files, fn(acc, item_name) {
    let nested_path = subdirectory_path <> "/" <> item_name
    case is_directory(nested_path) {
      True -> {
        use files_in_nested <- result.try(read_directory_or_error(nested_path))
        let json_files =
          extract_json_files_with_full_paths(files_in_nested, nested_path)
        Ok(list.append(acc, json_files))
      }
      False -> Ok(acc)
    }
  })
}

fn extract_json_files_with_full_paths(
  files: List(String),
  directory_path: String,
) -> List(String) {
  files
  |> list.filter(fn(file) { string.ends_with(file, ".json") })
  |> list.map(fn(file) { directory_path <> "/" <> file })
}

/// This function returns a list of all JSON files in the given directory.
pub fn get_instantiation_json_files(
  base_directory: String,
) -> Result(List(String), String) {
  use top_level_items <- result.try(read_directory_or_error(base_directory))

  top_level_items
  |> list.try_fold([], fn(accumulated_files, item_name) {
    process_top_level_item(base_directory, item_name, accumulated_files)
  })
}
