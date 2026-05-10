import caffeine_lang/linker/slo_params
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
import caffeine_lang/types
import gleam/dict
import gleeunit/should
import test_helpers

// ==== slo_params ====
// * ✅ returns expected number of params
pub fn slo_params_test() {
  let result = stdlib_artifacts.slo_params()

  [#("returns seven params", dict.size(result), 7)]
  |> test_helpers.table_test_1(fn(expected) { expected })
}

// ==== params_to_types ====
// * ✅ extracts types discarding descriptions
// * ✅ empty dict -> empty dict
pub fn params_to_types_test() {
  let params =
    dict.from_list([
      #(
        "env",
        slo_params.ParamInfo(
          type_: types.PrimitiveType(types.String),
          description: "The environment",
        ),
      ),
      #(
        "count",
        slo_params.ParamInfo(
          type_: types.PrimitiveType(types.NumericType(types.Integer)),
          description: "How many",
        ),
      ),
    ])

  let result = slo_params.params_to_types(params)
  dict.get(result, "env")
  |> should.equal(Ok(types.PrimitiveType(types.String)))
  dict.get(result, "count")
  |> should.equal(Ok(types.PrimitiveType(types.NumericType(types.Integer))))
  dict.size(result) |> should.equal(2)

  // Empty dict
  slo_params.params_to_types(dict.new())
  |> should.equal(dict.new())
}
