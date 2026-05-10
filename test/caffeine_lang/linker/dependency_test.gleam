import caffeine_lang/linker/dependency.{type DependencyRelationType, Hard, Soft}
import gleam/list
import gleeunit/should
import test_helpers

// ==== relation_type_to_string ====
// * ✅ Hard -> "hard"
// * ✅ Soft -> "soft"
pub fn relation_type_to_string_test() {
  [#("Hard", Hard, "hard"), #("Soft", Soft, "soft")]
  |> test_helpers.table_test_1(dependency.relation_type_to_string)
}

// ==== parse_relation_type ====
// * ✅ "hard" -> Ok(Hard)
// * ✅ "soft" -> Ok(Soft)
// * ❌ unknown -> Error(Nil)
pub fn parse_relation_type_test() {
  [
    #("hard", "hard", Ok(Hard)),
    #("soft", "soft", Ok(Soft)),
    #("unknown", "other", Error(Nil)),
    #("capitalized", "Hard", Error(Nil)),
  ]
  |> test_helpers.table_test_1(dependency.parse_relation_type)
}

// ==== parse/to_string round trips ====
// * ✅ relation_type round-trips
pub fn relation_type_round_trip_test() {
  [Hard, Soft]
  |> list.each(fn(t: DependencyRelationType) {
    dependency.relation_type_to_string(t)
    |> dependency.parse_relation_type
    |> should.equal(Ok(t))
  })
}
