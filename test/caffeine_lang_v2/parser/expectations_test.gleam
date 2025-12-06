// ==== Tests - Expectations ====
// ==== Happy Path ====
// * ❌ none
// * ❌ single
// * ❌ multiple
// ==== Empty ====
// * ❌ inputs - (empty dictionary)
// * ❌ expectations
// * ❌ name
// * ❌ blueprint
// ==== Missing ====
// * ❌ content (empty file)
// * ❌ expectations
// * ❌ name
// * ❌ blueprint
// * ❌ inputs
// ==== Duplicates ====
// * ❌ name (all expectations must be unique)
// * ❌ inputs (all inputs must have unique labels)
// ==== Wrong Types ====
// * ❌ expectations
// * ❌ name
// * ❌ blueprint
// * ❌ inputs (we will initially interpret all as String and later attempt to coalesce to the proper type)
