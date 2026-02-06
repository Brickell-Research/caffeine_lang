import caffeine_lang/string_distance
import gleam/option
import test_helpers

// ==== levenshtein ====
// * ✅ empty strings
// * ✅ identical strings
// * ✅ single insertion
// * ✅ single deletion
// * ✅ single substitution
// * ✅ multiple edits
// * ✅ completely different
// * ✅ case sensitive
pub fn levenshtein_test() {
  [
    #("", "", 0),
    #("hello", "hello", 0),
    #("cat", "cats", 1),
    #("cats", "cat", 1),
    #("cat", "car", 1),
    #("kitten", "sitting", 3),
    #("abc", "xyz", 3),
    #("String", "string", 1),
  ]
  |> test_helpers.array_based_test_executor_2(string_distance.levenshtein)
}

// ==== closest_match ====
// * ✅ exact match returns it
// * ✅ close match within threshold
// * ✅ no match when too far
// * ✅ empty candidates returns None
// * ✅ picks closest among multiple candidates
// * ✅ type name typo scenario
pub fn closest_match_test() {
  [
    // Exact match
    #("String", ["String", "Integer", "Float"], option.Some("String")),
    // Close match (1 edit: Strin -> String)
    #("Strin", ["String", "Integer", "Float"], option.Some("String")),
    // Too far (abc -> String is distance 6)
    #("abc", ["String", "Integer", "Float"], option.None),
    // Empty candidates
    #("String", [], option.None),
    // Picks closest
    #("Integr", ["String", "Integer", "Float"], option.Some("Integer")),
    // Type name typo
    #("Boolan", ["Boolean", "String", "Integer"], option.Some("Boolean")),
  ]
  |> test_helpers.array_based_test_executor_2(string_distance.closest_match)
}
