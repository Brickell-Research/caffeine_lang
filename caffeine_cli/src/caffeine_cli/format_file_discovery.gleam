import gleam/bool
import gleam/list
import gleam/result
import gleam/string
import simplifile

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
    let full_path = dir <> "/" <> entry
    case simplifile.is_directory(full_path) {
      Ok(True) -> {
        use nested <- result.try(discover_in_directory(full_path))
        Ok(list.append(acc, nested))
      }
      _ -> {
        use <- bool.guard(
          string.ends_with(entry, ".caffeine"),
          Ok(list.append(acc, [full_path])),
        )
        Ok(acc)
      }
    }
  })
}
