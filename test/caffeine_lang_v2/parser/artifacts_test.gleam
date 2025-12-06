// ==== Tests - Artifacts ====
// ==== Happy Path ====
// * ❌ none
// * ❌ single artifact
// * ❌ multiple artifacts
// ==== Empty ====
// * ❌ base_params (empty dictionary)
// * ❌ params (empty dictionary)
// * ❌ content (empty file)
// * ❌ artifacts
// * ❌ name
// * ❌ version
// ==== Missing ====
// * ❌ name
// * ❌ version
// * ❌ base_params
// * ❌ params
// ==== Duplicates ====
// * ❌ name (all artifacts must be unique)
// * ❌ base_params (all base_params must have unique labels)
// * ❌ params (all params must have unique labels)
// ==== Wrong Types ====
// * ❌ artifacts
// * ❌ name
// * ❌ version
// * ❌ base_params
//  * ❌ base_params is a map
//  * ❌ each base_param's value is an Accepted Type
// * ❌ params
//  * ❌ params is a map
//  * ❌ each param's value is an Accepted Type
// ==== Semantic ====
// * ❌ version not semantic versioning
//   * ❌ no dots
//   * ❌ too many dots
//   * ❌ non numbers with two dots
//   * ❌ happy path
