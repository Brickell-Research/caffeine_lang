import caffeine_cli/format_file_discovery
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

// ==== discover ====
// * ✅ single .caffeine file returns it
// * ✅ directory with .caffeine files finds them
// * ✅ non-.caffeine file returns error
// * ✅ missing path returns error

pub fn discover_single_file_test() {
  let dir = "test/caffeine_cli/tmp_discover_single"
  let file = dir <> "/test.caffeine"
  let _ = simplifile.create_directory_all(dir)
  let _ = simplifile.write(file, "Blueprints for \"SLO\"\n")

  let result = format_file_discovery.discover(file)
  result |> should.be_ok()
  let assert Ok(files) = result
  files |> should.equal([file])

  // Cleanup
  let _ = simplifile.delete(file)
  let _ = simplifile.delete(dir)
}

pub fn discover_directory_test() {
  let dir = "test/caffeine_cli/tmp_discover_dir"
  let _ = simplifile.create_directory_all(dir)
  let _ = simplifile.write(dir <> "/a.caffeine", "")
  let _ = simplifile.write(dir <> "/b.caffeine", "")
  let _ = simplifile.write(dir <> "/c.txt", "")

  let result = format_file_discovery.discover(dir)
  result |> should.be_ok()
  let assert Ok(files) = result
  // Should find only .caffeine files
  list.length(files) |> should.equal(2)
  list.each(files, fn(f) {
    { string.ends_with(f, ".caffeine") } |> should.be_true()
  })

  // Cleanup
  let _ = simplifile.delete(dir <> "/a.caffeine")
  let _ = simplifile.delete(dir <> "/b.caffeine")
  let _ = simplifile.delete(dir <> "/c.txt")
  let _ = simplifile.delete(dir)
}

pub fn discover_non_caffeine_file_error_test() {
  format_file_discovery.discover("test/caffeine_cli/nonexistent.txt")
  |> should.be_error()
}

pub fn discover_missing_path_error_test() {
  format_file_discovery.discover("test/caffeine_cli/does_not_exist.caffeine")
  |> should.be_error()
}
