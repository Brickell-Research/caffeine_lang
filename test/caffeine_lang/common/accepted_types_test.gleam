import caffeine_lang/common/accepted_types
import test_helpers

// ==== Accepted Type To String Tests ====
// * ✅ Boolean
// * ✅ Float
// * ✅ Integer
// * ✅ String
// * ✅ Dict(String, String)
// * ✅ Dict(String, Integer)
// * ✅ Dict(String, Float)
// * ✅ Dict(String, Boolean)
// * ✅ List(String)
// * ✅ List(Integer)
// * ✅ List(Float)
// * ✅ List(Boolean)
// * ✅ Optional(String)
// * ✅ Optional(Integer)
// * ✅ Optional(Float)
// * ✅ Optional(Boolean)
// * ✅ Optional(List(String))
// * ✅ Optional(Dict(String, String))
// * ✅ Defaulted(String, default)
// * ✅ Defaulted(Integer, 10)
// * ✅ Defaulted(List(String), default)
// * ✅ Defaulted(Dict(String, String), default)
pub fn accepted_type_to_string_test() {
  [
    #(accepted_types.Boolean, "Boolean"),
    #(accepted_types.Float, "Float"),
    #(accepted_types.Integer, "Integer"),
    #(accepted_types.String, "String"),
    #(
      accepted_types.Dict(accepted_types.String, accepted_types.String),
      "Dict(String, String)",
    ),
    #(
      accepted_types.Dict(accepted_types.String, accepted_types.Integer),
      "Dict(String, Integer)",
    ),
    #(
      accepted_types.Dict(accepted_types.String, accepted_types.Float),
      "Dict(String, Float)",
    ),
    #(
      accepted_types.Dict(accepted_types.String, accepted_types.Boolean),
      "Dict(String, Boolean)",
    ),
    #(accepted_types.List(accepted_types.String), "List(String)"),
    #(accepted_types.List(accepted_types.Integer), "List(Integer)"),
    #(accepted_types.List(accepted_types.Float), "List(Float)"),
    #(accepted_types.List(accepted_types.Boolean), "List(Boolean)"),
    // Optional basic types
    #(accepted_types.Optional(accepted_types.String), "Optional(String)"),
    #(accepted_types.Optional(accepted_types.Integer), "Optional(Integer)"),
    #(accepted_types.Optional(accepted_types.Float), "Optional(Float)"),
    #(accepted_types.Optional(accepted_types.Boolean), "Optional(Boolean)"),
    // Optional nested types
    #(
      accepted_types.Optional(accepted_types.List(accepted_types.String)),
      "Optional(List(String))",
    ),
    #(
      accepted_types.Optional(
        accepted_types.Dict(accepted_types.String, accepted_types.String),
      ),
      "Optional(Dict(String, String))",
    ),
    // Defaulted basic types
    #(
      accepted_types.Defaulted(accepted_types.String, "default"),
      "Defaulted(String, default)",
    ),
    #(
      accepted_types.Defaulted(accepted_types.Integer, "10"),
      "Defaulted(Integer, 10)",
    ),
    // Defaulted nested types
    #(
      accepted_types.Defaulted(
        accepted_types.List(accepted_types.String),
        "default",
      ),
      "Defaulted(List(String), default)",
    ),
    #(
      accepted_types.Defaulted(
        accepted_types.Dict(accepted_types.String, accepted_types.String),
        "default",
      ),
      "Defaulted(Dict(String, String), default)",
    ),
  ]
  |> test_helpers.array_based_test_executor_1(
    accepted_types.accepted_type_to_string,
  )
}
