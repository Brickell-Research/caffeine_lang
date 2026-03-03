import caffeine_lang/linker/artifacts
import test_helpers

// ==== parse_relation_type ====
// * ✅ parses "hard" to Hard
// * ✅ parses "soft" to Soft
// * ✅ unknown string returns Error
pub fn parse_relation_type_test() {
  [
    #("parses hard", "hard", Ok(artifacts.Hard)),
    #("parses soft", "soft", Ok(artifacts.Soft)),
    #("unknown returns error", "unknown", Error(Nil)),
  ]
  |> test_helpers.table_test_1(artifacts.parse_relation_type)
}

// ==== relation_type_to_string ====
// * ✅ Hard to "hard"
// * ✅ Soft to "soft"
pub fn relation_type_to_string_test() {
  [
    #("Hard to hard", artifacts.Hard, "hard"),
    #("Soft to soft", artifacts.Soft, "soft"),
  ]
  |> test_helpers.table_test_1(artifacts.relation_type_to_string)
}
