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
    #("empty strings", "", "", 0),
    #("identical strings", "hello", "hello", 0),
    #("single insertion", "cat", "cats", 1),
    #("single deletion", "cats", "cat", 1),
    #("single substitution", "cat", "car", 1),
    #("multiple edits", "kitten", "sitting", 3),
    #("completely different", "abc", "xyz", 3),
    #("case sensitive", "String", "string", 1),
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
    #(
      "exact match returns it",
      "String",
      ["String", "Integer", "Float"],
      option.Some("String"),
    ),
    // Close match (1 edit: Strin -> String)
    #(
      "close match within threshold",
      "Strin",
      ["String", "Integer", "Float"],
      option.Some("String"),
    ),
    // Too far (abc -> String is distance 6)
    #(
      "no match when too far",
      "abc",
      ["String", "Integer", "Float"],
      option.None,
    ),
    // Empty candidates
    #("empty candidates returns None", "String", [], option.None),
    // Picks closest
    #(
      "picks closest among multiple candidates",
      "Integr",
      ["String", "Integer", "Float"],
      option.Some("Integer"),
    ),
    // Type name typo
    #(
      "type name typo scenario",
      "Boolan",
      ["Boolean", "String", "Integer"],
      option.Some("Boolean"),
    ),
  ]
  |> test_helpers.array_based_test_executor_2(string_distance.closest_match)
}
