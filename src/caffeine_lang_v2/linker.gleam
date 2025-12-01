import caffeine_lang_v2/common/ast.{type AST}
import caffeine_lang_v2/parser/artifacts.{type Artifact}
import caffeine_lang_v2/parser/blueprints.{type Blueprint}
import caffeine_lang_v2/parser/expectations.{type Expectation}
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub fn standard_library_directory() -> String {
  "src/caffeine_lang_v2/standard_library"
}

/// Link will fetch, then parse all configuration files, combining them into one single
/// abstract syntax tree (AST) object. In the future how we fetch these files will
/// change to enble fetching from remote locations, via git, etc. but for now we
/// just support standard library artifacts, a single blueprint file, and a single
/// expectations directory. Furthermore note that we will ignore non-yaml files within
/// an org's team's expectation directory and incorrectly placed yaml files will also
/// be ignored.
pub fn link(
  blueprint_file_path: String,
  expectations_directory: String,
) -> Result(AST, String) {
  use artifacts <- result.try(fetch_artifacts())
  use blueprints <- result.try(fetch_blueprints(blueprint_file_path))
  use expectations <- result.try(fetch_expectations(expectations_directory))

  Ok(ast.AST(artifacts:, blueprints:, expectations:))
}

fn fetch_artifacts() -> Result(List(Artifact), String) {
  artifacts.parse(standard_library_directory() <> "/artifacts.yaml")
}

fn fetch_blueprints(
  blueprint_file_path: String,
) -> Result(List(Blueprint), String) {
  blueprints.parse(blueprint_file_path)
}

fn fetch_expectations(
  expectations_directory: String,
) -> Result(List(Expectation), String) {
  use expectations_files <- result.try(get_instantiation_yaml_files(
    expectations_directory,
  ))

  case expectations_files {
    [] -> Error("No expectation files found in: " <> expectations_directory)
    _ ->
      expectations_files
      |> list.map(fn(file_path) { expectations.parse(file_path) })
      |> result.all()
      |> result.map(list.flatten)
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
    True -> collect_yaml_files_from_subdirectory(item_path, accumulated_files)
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

fn collect_yaml_files_from_subdirectory(
  subdirectory_path: String,
  accumulated_files: List(String),
) -> Result(List(String), String) {
  use items_in_subdirectory <- result.try(read_directory_or_error(
    subdirectory_path,
  ))

  // Go one level deeper - iterate over nested directories and collect YAML files from each
  items_in_subdirectory
  |> list.try_fold(accumulated_files, fn(acc, item_name) {
    let nested_path = subdirectory_path <> "/" <> item_name
    case is_directory(nested_path) {
      True -> {
        use files_in_nested <- result.try(read_directory_or_error(nested_path))
        let yaml_files =
          extract_yaml_files_with_full_paths(files_in_nested, nested_path)
        Ok(list.append(acc, yaml_files))
      }
      False -> Ok(acc)
    }
  })
}

fn extract_yaml_files_with_full_paths(
  files: List(String),
  directory_path: String,
) -> List(String) {
  files
  |> list.filter(fn(file) { string.ends_with(file, ".yaml") })
  |> list.map(fn(file) { directory_path <> "/" <> file })
}

/// This function returns a list of all YAML files in the given directory.
/// Results are sorted for deterministic ordering across platforms.
pub fn get_instantiation_yaml_files(
  base_directory: String,
) -> Result(List(String), String) {
  use top_level_items <- result.try(read_directory_or_error(base_directory))

  top_level_items
  |> list.try_fold([], fn(accumulated_files, item_name) {
    process_top_level_item(base_directory, item_name, accumulated_files)
  })
  |> result.map(list.sort(_, string.compare))
}
