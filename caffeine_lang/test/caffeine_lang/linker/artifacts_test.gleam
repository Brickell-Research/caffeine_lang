import caffeine_lang/linker/artifacts.{
  type ArtifactType, type DependencyRelationType, DependencyRelations, Hard, SLO,
  Soft,
}
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
import caffeine_lang/types
import gleam/dict
import gleam/list
import gleeunit/should
import test_helpers

// ==== standard_library ====
// * ✅ returns two artifacts (SLO and DependencyRelations)
// * ✅ artifact types match expected
pub fn standard_library_test() {
  let result = stdlib_artifacts.standard_library()

  [
    #("returns two artifacts", list.length(result), 2),
  ]
  |> test_helpers.table_test_1(fn(expected) { expected })

  let types =
    result
    |> list.map(fn(a) { artifacts.artifact_type_to_string(a.type_) })

  [
    #("contains SLO artifact", list.contains(types, "SLO"), True),
    #(
      "contains DependencyRelations artifact",
      list.contains(types, "DependencyRelations"),
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(val) { val })
}

// ==== artifact_type_to_string ====
// * ✅ SLO → "SLO"
// * ✅ DependencyRelations → "DependencyRelations"
pub fn artifact_type_to_string_test() {
  [
    #("SLO", SLO, "SLO"),
    #("DependencyRelations", DependencyRelations, "DependencyRelations"),
  ]
  |> test_helpers.table_test_1(artifacts.artifact_type_to_string)
}

// ==== parse_artifact_type ====
// * ✅ "SLO" → Ok(SLO)
// * ✅ "DependencyRelations" → Ok(DependencyRelations)
// * ❌ unknown → Error(Nil)
pub fn parse_artifact_type_test() {
  [
    #("SLO", "SLO", Ok(SLO)),
    #("DependencyRelations", "DependencyRelations", Ok(DependencyRelations)),
    #("unknown", "Unknown", Error(Nil)),
    #("empty", "", Error(Nil)),
  ]
  |> test_helpers.table_test_1(artifacts.parse_artifact_type)
}

// ==== relation_type_to_string ====
// * ✅ Hard → "hard"
// * ✅ Soft → "soft"
pub fn relation_type_to_string_test() {
  [
    #("Hard", Hard, "hard"),
    #("Soft", Soft, "soft"),
  ]
  |> test_helpers.table_test_1(artifacts.relation_type_to_string)
}

// ==== parse_relation_type ====
// * ✅ "hard" → Ok(Hard)
// * ✅ "soft" → Ok(Soft)
// * ❌ unknown → Error(Nil)
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
// * ✅ artifact_type round-trips
// * ✅ relation_type round-trips
pub fn artifact_type_round_trip_test() {
  [SLO, DependencyRelations]
  |> list.each(fn(t: ArtifactType) {
    artifacts.artifact_type_to_string(t)
    |> artifacts.parse_artifact_type
    |> should.equal(Ok(t))
  })
}

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
// * ✅ empty dict → empty dict
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
