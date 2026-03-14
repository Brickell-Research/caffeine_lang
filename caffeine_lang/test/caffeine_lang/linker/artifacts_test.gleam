import caffeine_lang/linker/artifacts.{type DependencyRelationType, Hard, Soft}
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
import caffeine_lang/types
import gleam/dict
import gleam/list
import gleeunit/should
import test_helpers

// ==== slo_params ====
// * ✅ returns expected number of params
pub fn slo_params_test() {
  let result = stdlib_artifacts.slo_params()

  [
    #("returns seven params", dict.size(result), 7),
  ]
  |> test_helpers.table_test_1(fn(expected) { expected })
}

// ==== relation_type_to_string ====
// * ✅ Hard -> "hard"
// * ✅ Soft -> "soft"
pub fn relation_type_to_string_test() {
  [
    #("Hard", Hard, "hard"),
    #("Soft", Soft, "soft"),
  ]
  |> test_helpers.table_test_1(artifacts.relation_type_to_string)
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
  |> test_helpers.table_test_1(artifacts.parse_relation_type)
}

// ==== parse/to_string round trips ====
// * ✅ relation_type round-trips
pub fn relation_type_round_trip_test() {
  [Hard, Soft]
  |> list.each(fn(t: DependencyRelationType) {
    artifacts.relation_type_to_string(t)
    |> artifacts.parse_relation_type
    |> should.equal(Ok(t))
  })
}

// ==== params_to_types ====
// * ✅ extracts types discarding descriptions
// * ✅ empty dict -> empty dict
pub fn params_to_types_test() {
  let params =
    dict.from_list([
      #(
        "env",
        artifacts.ParamInfo(
          type_: types.PrimitiveType(types.String),
          description: "The environment",
        ),
      ),
      #(
        "count",
        artifacts.ParamInfo(
          type_: types.PrimitiveType(types.NumericType(types.Integer)),
          description: "How many",
        ),
      ),
    ])

  let result = artifacts.params_to_types(params)
  dict.get(result, "env")
  |> should.equal(Ok(types.PrimitiveType(types.String)))
  dict.get(result, "count")
  |> should.equal(Ok(types.PrimitiveType(types.NumericType(types.Integer))))
  dict.size(result) |> should.equal(2)

  // Empty dict
  artifacts.params_to_types(dict.new())
  |> should.equal(dict.new())
}
