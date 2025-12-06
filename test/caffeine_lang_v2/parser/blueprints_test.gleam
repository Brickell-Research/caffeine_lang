// ==== Tests - Blueprints ====
// ==== Happy Path ====
// * ❌ none
// * ❌ single blueprint
// * ❌ multiple blueprints
// ==== Empty ====
// * ❌ params (empty dictionary)
// * ❌ inputs (empty dictionary)
// * ❌ content (empty file)
// * ❌ blueprint
// * ❌ name
// * ❌ artifact
// ==== Missing ====
// * ❌ name
// * ❌ artifact
// * ❌ params
// * ❌ inputs
// ==== Duplicates ====
// * ❌ name (all blueprints must be unique)
// * ❌ params (all params must have unique labels)
// * ❌ inputs (all inputs must have unique labels)
// ==== Wrong Types ====
// * ❌ blueprint
// * ❌ name
// * ❌ artifact
// * ❌ params
//  * ❌ params is a map
//  * ❌ each param's value is an Accepted Type
// * ❌ inputs
//  * ❌ inputs is a map
//  * ❌ each input is a string
