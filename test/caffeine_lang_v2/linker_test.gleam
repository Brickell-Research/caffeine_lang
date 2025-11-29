import caffeine_lang_v2/linker
import gleeunit/should

// ==== Tests ====
// * ✅ happy path - simple
// * ✅ happy path - same name expectations across different teams and different orgs
// * ❌ cannot find artifacts (requires modifying standard library path, skipped)
// * ✅ cannot find blueprints
// * ✅ cannot find expectations
// * ❌ artifacts parse error (requires modifying standard library, skipped)
// * ✅ blueprints parse error
// * ✅ expectations parse error
// * ✅ empty expectations directory

const base_path = "test/caffeine_lang_v2/artifacts/linker_tests"

// ==== Happy Path ====

pub fn link_happy_path_simple_test() {
  let blueprint_path = base_path <> "/happy_path_simple/blueprints.yaml"
  let expectations_path = base_path <> "/happy_path_simple/expectations"

  let result = linker.link(blueprint_path, expectations_path)

  should.be_ok(result)
}

pub fn link_happy_path_same_name_across_teams_test() {
  let blueprint_path = base_path <> "/happy_path_same_name/blueprints.yaml"
  let expectations_path = base_path <> "/happy_path_same_name/expectations"

  let result = linker.link(blueprint_path, expectations_path)

  // Same name expectations across different orgs/teams should work
  should.be_ok(result)
}

// ==== Cannot Find ====

pub fn link_cannot_find_blueprints_test() {
  let blueprint_path = base_path <> "/cannot_find_blueprints/nonexistent.yaml"
  let expectations_path = base_path <> "/cannot_find_blueprints"

  let result = linker.link(blueprint_path, expectations_path)

  should.be_error(result)
}

pub fn link_cannot_find_expectations_test() {
  let blueprint_path = base_path <> "/happy_path_simple/blueprints.yaml"
  let expectations_path = base_path <> "/cannot_find_expectations/nonexistent"

  let result = linker.link(blueprint_path, expectations_path)

  should.be_error(result)
}

// ==== Parse Errors ====

pub fn link_blueprints_parse_error_test() {
  let blueprint_path = base_path <> "/blueprints_parse_error/blueprints.yaml"
  let expectations_path = base_path <> "/blueprints_parse_error/expectations"

  let result = linker.link(blueprint_path, expectations_path)

  should.be_error(result)
}

pub fn link_expectations_parse_error_test() {
  let blueprint_path = base_path <> "/expectations_parse_error/blueprints.yaml"
  let expectations_path = base_path <> "/expectations_parse_error/expectations"

  let result = linker.link(blueprint_path, expectations_path)

  should.be_error(result)
}

// ==== Empty Directory ====

pub fn link_empty_expectations_directory_test() {
  let blueprint_path = base_path <> "/happy_path_simple/blueprints.yaml"
  let expectations_path = base_path <> "/empty_expectations_directory"

  let result = linker.link(blueprint_path, expectations_path)

  should.be_error(result)
}

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
