import caffeine_lang/common/errors
import caffeine_lang/parser/file_discovery
import gleam/list
import gleeunit/should
import test_helpers

const corpus_dir = "test/caffeine_lang/corpus/linker"

// ==== get_json_files ====
// * ✅ directory doesn't exist
// * ✅ nested directory structure (org/team/file.json)
// * ✅ mixed content - only json files collected
// * ✅ files at top level are skipped
// * ✅ empty subdirectories
pub fn get_json_files_test() {
  [
    #(
      "non_existent_directory",
      Error(errors.LinkerParseError(
        "No such file or directory (non_existent_directory)",
      )),
    ),
    #(
      corpus_dir <> "/nested_structure",
      Ok([corpus_dir <> "/nested_structure/org1/team1/expectation.json"]),
    ),
    #(
      corpus_dir <> "/mixed_content",
      Ok([corpus_dir <> "/mixed_content/org1/team1/valid.json"]),
    ),
    #(
      corpus_dir <> "/top_level_skipped",
      Ok([corpus_dir <> "/top_level_skipped/org1/team1/nested.json"]),
    ),
    #(
      corpus_dir <> "/empty_subdirs",
      Ok([corpus_dir <> "/empty_subdirs/org1/team_with_files/test.json"]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(file_discovery.get_json_files)
}

// ==== get_json_files - multiple orgs/teams ====
// * ✅ collects files from multiple orgs and teams
// Note: order may vary due to filesystem, so we check contains instead of equals
pub fn get_json_files_multiple_orgs_teams_test() {
  let base = corpus_dir <> "/multiple_orgs_teams"
  let assert Ok(files) = file_discovery.get_json_files(base)

  files |> list.length |> should.equal(4)

  [
    base <> "/org1/team1/a.json",
    base <> "/org1/team1/b.json",
    base <> "/org1/team2/c.json",
    base <> "/org2/team1/d.json",
  ]
  |> list.each(fn(expected) {
    files |> list.contains(expected) |> should.be_true
  })
}

// ==== get_json_files - hidden files ====
// * ✅ hidden orgs are included
// * ✅ hidden teams are included
// * ✅ hidden files are included
// Note: order may vary due to filesystem, so we check contains instead of equals
// TODO: wondering if maybe we don't want this? When would we ever actually have things
//       in hidden directories?
pub fn get_json_files_hidden_files_test() {
  let base = corpus_dir <> "/hidden_files"
  let assert Ok(files) = file_discovery.get_json_files(base)

  files |> list.length |> should.equal(4)

  [
    base <> "/.hidden_org/team1/config.json",
    base <> "/org1/.hidden_team/secret.json",
    base <> "/org1/team1/.hidden.json",
    base <> "/org1/team1/visible.json",
  ]
  |> list.each(fn(expected) {
    files |> list.contains(expected) |> should.be_true
  })
}
