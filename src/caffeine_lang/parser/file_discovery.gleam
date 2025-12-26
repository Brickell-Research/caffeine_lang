import gleam/list
import gleam/result
import gleam/string
import simplifile

fn read_directory_or_error(
  directory_path: String,
) -> Result(List(String), String) {
  case simplifile.read_directory(directory_path) {
    Ok(items) -> Ok(items)
    Error(err) ->
      Error(simplifile.describe_error(err)
        <> " ("
        <> directory_path
        <> ")")
  }
}

fn process_top_level_item(
  base_directory: String,
  item_name: String,
  accumulated_files: List(String),
) -> Result(List(String), String) {
  let item_path = base_directory <> "/" <> item_name

  case simplifile.is_directory(item_path) {
    Ok(True) ->
      collect_json_files_from_subdirectory(item_path, accumulated_files)
    _ -> Ok(accumulated_files)
    // Skip files at the top level
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
    case simplifile.is_directory(nested_path) {
      Ok(True) -> {
        use files_in_nested <- result.try(read_directory_or_error(nested_path))
        let json_files =
          extract_json_files_with_full_paths(files_in_nested, nested_path)
        Ok(list.append(acc, json_files))
      }
      _ -> Ok(acc)
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
@internal
pub fn get_json_files(
  base_directory: String,
) -> Result(List(String), String) {
  use top_level_items <- result.try(read_directory_or_error(base_directory))

  top_level_items
  |> list.try_fold([], fn(accumulated_files, item_name) {
    process_top_level_item(base_directory, item_name, accumulated_files)
  })
}
