import caffeine_lang/errors.{type CompilationError}
import filepath
import gleam/bool
import gleam/list
import gleam/result
import gleam/string
import simplifile

/// Returns a list of all .caffeine files in the given directory.
/// Uses a fixed two-level depth (org/team/file.caffeine).
@internal
pub fn get_caffeine_files(
  base_directory: String,
) -> Result(List(String), CompilationError) {
  use top_level_items <- result.try(read_directory_or_error(base_directory))

  top_level_items
  |> list.try_fold([], fn(accumulated_files, item_name) {
    process_top_level_item(base_directory, item_name, accumulated_files)
  })
}

/// Discover .caffeine files from a path.
/// If path is a .caffeine file, return it as a single-element list.
/// If path is a directory, recursively find all .caffeine files.
/// Otherwise, return an error.
@internal
pub fn discover(path: String) -> Result(List(String), String) {
  use <- bool.guard(
    string.ends_with(path, ".caffeine"),
    case simplifile.is_file(path) {
      Ok(True) -> Ok([path])
      _ -> Error("File not found: " <> path)
    },
  )
  case simplifile.is_directory(path) {
    Ok(True) -> discover_in_directory(path)
    _ -> Error("Path is not a .caffeine file or directory: " <> path)
  }
}

// --- Fixed-depth helpers (compile) ---

fn read_directory_or_error(
  directory_path: String,
) -> Result(List(String), CompilationError) {
  case simplifile.read_directory(directory_path) {
    Ok(items) -> Ok(items)
    Error(err) ->
      Error(errors.LinkerParseError(
        msg: simplifile.describe_error(err) <> " (" <> directory_path <> ")",
        context: errors.empty_context(),
      ))
  }
}

fn process_top_level_item(
  base_directory: String,
  item_name: String,
  accumulated_files: List(String),
) -> Result(List(String), CompilationError) {
  let item_path = filepath.join(base_directory, item_name)

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
    let nested_path = filepath.join(subdirectory_path, item_name)
    case simplifile.is_directory(nested_path) {
      Ok(True) -> {
        use files_in_nested <- result.try(read_directory_or_error(nested_path))
        let caffeine_files =
          extract_caffeine_files_with_full_paths(files_in_nested, nested_path)
        Ok(list.append(caffeine_files, acc))
      }
      _ -> Ok(acc)
    }
  })
  |> result.map(list.reverse)
}

fn extract_caffeine_files_with_full_paths(
  files: List(String),
  directory_path: String,
) -> List(String) {
  files
  |> list.filter(fn(file) { string.ends_with(file, ".caffeine") })
  |> list.map(fn(file) { filepath.join(directory_path, file) })
}

// --- Recursive helpers (format) ---

fn discover_in_directory(dir: String) -> Result(List(String), String) {
  use entries <- result.try(
    simplifile.read_directory(dir)
    |> result.map_error(fn(err) {
      "Error reading directory: "
      <> simplifile.describe_error(err)
      <> " ("
      <> dir
      <> ")"
    }),
  )

  entries
  |> list.try_fold([], fn(acc, entry) {
    let full_path = filepath.join(dir, entry)
    case simplifile.is_directory(full_path) {
      Ok(True) -> {
        use nested <- result.try(discover_in_directory(full_path))
        Ok(list.append(nested, acc))
      }
      _ -> {
        use <- bool.guard(
          string.ends_with(entry, ".caffeine"),
          Ok([full_path, ..acc]),
        )
        Ok(acc)
      }
    }
  })
  |> result.map(list.reverse)
}
