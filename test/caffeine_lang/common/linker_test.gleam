import caffeine_lang/parser/linker
import gleam/list
import gleeunit/should

// ==== get_instantiation_json_files Tests ====
// * ✅ directory doesn't exist
// * ✅ nested directory structure (org/team/file.json)
// * ✅ mixed content - only json files collected
// * ✅ files at top level are skipped
// * ✅ empty subdirectories
// * ✅ multiple orgs, multiple teams
// * ✅ hidden files and directories are included

const corpus_dir = "test/caffeine_lang/corpus/linker"

pub fn get_instantiation_json_files_test() {
  [
    #(
      "non_existent_directory",
      Error("No such file or directory (non_existent_directory)"),
    ),
    #(
      corpus_dir <> "/nested_structure",
      Ok([
        corpus_dir <> "/nested_structure/org1/team1/expectation.json",
      ]),
    ),
    #(
      corpus_dir <> "/mixed_content",
      Ok([
        corpus_dir <> "/mixed_content/org1/team1/valid.json",
      ]),
    ),
    #(
      corpus_dir <> "/top_level_skipped",
      Ok([
        corpus_dir <> "/top_level_skipped/org1/team1/nested.json",
      ]),
    ),
    #(
      corpus_dir <> "/empty_subdirs",
      Ok([
        corpus_dir <> "/empty_subdirs/org1/team_with_files/test.json",
      ]),
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    linker.get_instantiation_json_files(input)
    |> should.equal(expected)
  })
}

pub fn get_instantiation_json_files_multiple_orgs_teams_test() {
  let base = corpus_dir <> "/multiple_orgs_teams"
  let result = linker.get_instantiation_json_files(base)
  result |> should.be_ok

  let assert Ok(files) = result
  list.length(files) |> should.equal(4)

  // Order may vary due to filesystem
  [
    base <> "/org1/team1/a.json",
    base <> "/org1/team1/b.json",
    base <> "/org1/team2/c.json",
    base <> "/org2/team1/d.json",
  ]
  |> list.each(fn(expected_file) {
    files |> list.contains(expected_file) |> should.be_true
  })
}

pub fn get_instantiation_json_files_hidden_files_included_test() {
  let base = corpus_dir <> "/hidden_files"
  let result = linker.get_instantiation_json_files(base)
  result |> should.be_ok

  let assert Ok(files) = result
  list.length(files) |> should.equal(4)

  // Order may vary due to filesystem
  [
    base <> "/.hidden_org/team1/config.json",
    base <> "/org1/.hidden_team/secret.json",
    base <> "/org1/team1/.hidden.json",
    base <> "/org1/team1/visible.json",
  ]
  |> list.each(fn(expected_file) {
    files |> list.contains(expected_file) |> should.be_true
  })
}
