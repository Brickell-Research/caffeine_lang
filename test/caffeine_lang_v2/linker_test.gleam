import caffeine_lang_v2/linker
import gleeunit/should

// ==== Tests ====
// * ❌ happy path - simple
// * ❌ happy path - same name expectations across different teams and different orgs
// * ❌ cannot find artifacts
// * ❌ cannot find blueprints
// * ❌ cannot find expectations
// * ❌ artifacts parse error
// * ❌ blueprints parse error
// * ❌ expectations parse error

// ==== Helpers ====
// * get_instantiation_yaml_files
//   * gets all files we'd expect - ignoring empty directories and non-yaml files

pub fn get_instantiation_yaml_files_test() {
  let directory =
    "test/caffeine_lang_v2/artifacts/linker_tests/get_instantiation_yaml_files_test"

  let expected =
    Ok([
      directory <> "/org_b/team_c/service_b.yaml",
      directory <> "/org_a/team_b/service_b.yaml",
      directory <> "/org_a/team_b/service_a.yaml",
    ])

  let actual = linker.get_instantiation_yaml_files(directory)

  should.equal(expected, actual)
}
