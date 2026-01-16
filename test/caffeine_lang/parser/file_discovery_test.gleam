import caffeine_lang/common/errors
import caffeine_lang/parser/file_discovery
import gleam/list
import gleeunit/should
import test_helpers

const corpus_dir = "test/caffeine_lang/corpus/linker"

// ==== get_caffeine_files ====
// * ✅ directory doesn't exist
// * ✅ nested directory structure (org/team/file.caffeine)
// * ✅ mixed content - only json files collected
// * ✅ files at top level are skipped
// * ✅ empty subdirectories
pub fn get_caffeine_files_test() {
  [
    #(
      "non_existent_directory",
      Error(errors.LinkerParseError(
        "No such file or directory (non_existent_directory)",
      )),
    ),
    #(
      corpus_dir <> "/nested_structure",
      Ok([corpus_dir <> "/nested_structure/org1/team1/expectation.caffeine"]),
    ),
    #(
      corpus_dir <> "/mixed_content",
      Ok([corpus_dir <> "/mixed_content/org1/team1/valid.caffeine"]),
    ),
    #(
      corpus_dir <> "/top_level_skipped",
      Ok([corpus_dir <> "/top_level_skipped/org1/team1/nested.caffeine"]),
    ),
    #(
      corpus_dir <> "/empty_subdirs",
      Ok([corpus_dir <> "/empty_subdirs/org1/team_with_files/test.caffeine"]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(file_discovery.get_caffeine_files)
}

// ==== get_caffeine_files - multiple orgs/teams ====
// * ✅ collects files from multiple orgs and teams
// Note: order may vary due to filesystem, so we check contains instead of equals
pub fn get_caffeine_files_multiple_orgs_teams_test() {
  let base = corpus_dir <> "/multiple_orgs_teams"
  let assert Ok(files) = file_discovery.get_caffeine_files(base)

  files |> list.length |> should.equal(4)

  [
    base <> "/org1/team1/a.caffeine",
    base <> "/org1/team1/b.caffeine",
    base <> "/org1/team2/c.caffeine",
    base <> "/org2/team1/d.caffeine",
  ]
  |> list.each(fn(expected) {
    files |> list.contains(expected) |> should.be_true
  })
}

// ==== get_caffeine_files - hidden files ====
// * ✅ hidden orgs are included
// * ✅ hidden teams are included
// * ✅ hidden files are included
// Note: order may vary due to filesystem, so we check contains instead of equals
// TODO: wondering if maybe we don't want this? When would we ever actually have things
//       in hidden directories?
pub fn get_caffeine_files_hidden_files_test() {
  let base = corpus_dir <> "/hidden_files"
  let assert Ok(files) = file_discovery.get_caffeine_files(base)

  files |> list.length |> should.equal(4)

  [
    base <> "/.hidden_org/team1/config.caffeine",
    base <> "/org1/.hidden_team/secret.caffeine",
    base <> "/org1/team1/.hidden.caffeine",
    base <> "/org1/team1/visible.caffeine",
  ]
  |> list.each(fn(expected) {
    files |> list.contains(expected) |> should.be_true
  })
}
