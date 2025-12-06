// ==== Tests ====
// * ❌ happy path - simple
// * ❌ happy path - same name expectations across different teams and different orgs
// * ❌ cannot find artifacts (requires modifying standard library path, skipped)
// * ❌ cannot find blueprints
// * ❌ cannot find expectations
// * ❌ artifacts parse error (requires modifying standard library, skipped)
// * ❌ blueprints parse error
// * ❌ expectations parse error
// * ❌ empty expectations directory

// ==== Helpers ====
// * get_instantiation_yaml_files
//   * gets all files we'd expect - ignoring empty directories and non-yaml files
