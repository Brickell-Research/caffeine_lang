import caffeine_lang/common/errors.{type CompilationError}
import gleam/list
import gleam/result
import gleam/string
import simplifile

/// Returns a list of all .caffeine files in the given directory.
@internal
pub fn get_caffeine_files(
  base_directory: String,
) -> Result(List(String), CompilationError) {
  use top_level_items <- result.try(read_directory_or_error(base_directory))

  let file_paths =
    top_level_items
    |> list.try_fold([], fn(accumulated_files, item_name) {
      process_top_level_item(base_directory, item_name, accumulated_files)
    })

  case file_paths {
    Error(err) -> Error(err)
    Ok(files) -> Ok(files)
  }
}

fn read_directory_or_error(
  directory_path: String,
) -> Result(List(String), CompilationError) {
  case simplifile.read_directory(directory_path) {
    Ok(items) -> Ok(items)
    Error(err) ->
      Error(errors.LinkerParseError(
        simplifile.describe_error(err) <> " (" <> directory_path <> ")",
      ))
  }
}

fn process_top_level_item(
  base_directory: String,
  item_name: String,
  accumulated_files: List(String),
) -> Result(List(String), CompilationError) {
  let item_path = base_directory <> "/" <> item_name

  case simplifile.is_directory(item_path) {
    Ok(True) ->
      collect_caffeine_files_from_subdirectory(item_path, accumulated_files)
    _ -> Ok(accumulated_files)
    // Skip files at the top level
  }
}

fn collect_caffeine_files_from_subdirectory(
  subdirectory_path: String,
  accumulated_files: List(String),
) -> Result(List(String), CompilationError) {
  use items_in_subdirectory <- result.try(read_directory_or_error(
    subdirectory_path,
  ))

  // Go one level deeper - iterate over nested directories and collect .caffeine files
  items_in_subdirectory
  |> list.try_fold(accumulated_files, fn(acc, item_name) {
    let nested_path = subdirectory_path <> "/" <> item_name
    case simplifile.is_directory(nested_path) {
      Ok(True) -> {
        use files_in_nested <- result.try(read_directory_or_error(nested_path))
        let caffeine_files =
          extract_caffeine_files_with_full_paths(files_in_nested, nested_path)
        Ok(list.append(acc, caffeine_files))
      }
      _ -> Ok(acc)
    }
  })
}

fn extract_caffeine_files_with_full_paths(
  files: List(String),
  directory_path: String,
) -> List(String) {
  files
  |> list.filter(fn(file) { string.ends_with(file, ".caffeine") })
  |> list.map(fn(file) { directory_path <> "/" <> file })
}
