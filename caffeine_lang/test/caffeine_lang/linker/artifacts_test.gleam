import caffeine_lang/linker/artifacts
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
import gleam/list
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
