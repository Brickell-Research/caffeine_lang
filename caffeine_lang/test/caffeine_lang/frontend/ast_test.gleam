import caffeine_lang/common/accepted_types
import caffeine_lang/common/primitive_types
import caffeine_lang/frontend/ast
import test_helpers

// ==== extendable_kind_to_string ====
// * ✅ ExtendableRequires -> "Requires"
// * ✅ ExtendableProvides -> "Provides"
pub fn extendable_kind_to_string_test() {
  [
    #(ast.ExtendableRequires, "Requires"),
    #(ast.ExtendableProvides, "Provides"),
  ]
  |> test_helpers.array_based_test_executor_1(ast.extendable_kind_to_string)
}

// ==== build_type_alias_pairs ====
// * ✅ empty list -> empty list
// * ✅ single alias -> single pair
// * ✅ multiple aliases -> multiple pairs
pub fn build_type_alias_pairs_test() {
  [
    #([], []),
    #(
      [
        ast.TypeAlias(
          "_env",
          accepted_types.PrimitiveType(primitive_types.String),
          [],
        ),
      ],
      [#("_env", accepted_types.PrimitiveType(primitive_types.String))],
    ),
    #(
      [
        ast.TypeAlias(
          "_env",
          accepted_types.PrimitiveType(primitive_types.String),
          [],
        ),
        ast.TypeAlias(
          "_count",
          accepted_types.PrimitiveType(primitive_types.Boolean),
          [],
        ),
      ],
      [
        #("_env", accepted_types.PrimitiveType(primitive_types.String)),
        #("_count", accepted_types.PrimitiveType(primitive_types.Boolean)),
      ],
    ),
  ]
  |> test_helpers.array_based_test_executor_1(ast.build_type_alias_pairs)
}

// ==== literal_to_string ====
// * ✅ String -> quoted string
// * ✅ Integer -> number string
// * ✅ Float -> number string
// * ✅ True -> "true"
// * ✅ False -> "false"
// * ✅ List -> "[...]"
// * ✅ Struct -> "{...}"
pub fn literal_to_string_test() {
  [
    #(ast.LiteralString("hello"), "\"hello\""),
    #(ast.LiteralInteger(42), "42"),
    #(ast.LiteralFloat(3.14), "3.14"),
    #(ast.LiteralTrue, "true"),
    #(ast.LiteralFalse, "false"),
    #(ast.LiteralList([]), "[...]"),
    #(ast.LiteralStruct([]), "{...}"),
  ]
  |> test_helpers.array_based_test_executor_1(ast.literal_to_string)
}
