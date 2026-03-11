import caffeine_lang/frontend/ast
import caffeine_lang/types
import test_helpers

// ==== extendable_kind_to_string ====
// * ✅ ExtendableRequires -> "Requires"
// * ✅ ExtendableProvides -> "Provides"
pub fn extendable_kind_to_string_test() {
  [
    #("ExtendableRequires -> Requires", ast.ExtendableRequires, "Requires"),
    #("ExtendableProvides -> Provides", ast.ExtendableProvides, "Provides"),
  ]
  |> test_helpers.table_test_1(ast.extendable_kind_to_string)
}

// ==== build_type_alias_pairs ====
// * ✅ empty list -> empty list
// * ✅ single alias -> single pair
// * ✅ multiple aliases -> multiple pairs
pub fn build_type_alias_pairs_test() {
  [
    #("empty list -> empty list", [], []),
    #(
      "single alias -> single pair",
      [
        ast.TypeAlias("_env", types.ParsedPrimitive(types.String), []),
      ],
      [#("_env", types.ParsedPrimitive(types.String))],
    ),
    #(
      "multiple aliases -> multiple pairs",
      [
        ast.TypeAlias("_env", types.ParsedPrimitive(types.String), []),
        ast.TypeAlias("_count", types.ParsedPrimitive(types.Boolean), []),
      ],
      [
        #("_env", types.ParsedPrimitive(types.String)),
        #("_count", types.ParsedPrimitive(types.Boolean)),
      ],
    ),
  ]
  |> test_helpers.table_test_1(ast.build_type_alias_pairs)
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
    #("String -> quoted string", ast.LiteralString("hello"), "\"hello\""),
    #("Integer -> number string", ast.LiteralInteger(42), "42"),
    #("Float -> number string", ast.LiteralFloat(3.14), "3.14"),
    #("True -> true", ast.LiteralTrue, "true"),
    #("False -> false", ast.LiteralFalse, "false"),
    #("List -> [...]", ast.LiteralList([]), "[...]"),
    #("Struct -> {...}", ast.LiteralStruct([], []), "{...}"),
    #("Percentage -> number%", ast.LiteralPercentage(99.9), "99.9%"),
  ]
  |> test_helpers.table_test_1(ast.literal_to_string)
}

// ==== parsed_artifact_ref_to_string ====
// * ✅ ParsedSLO -> "SLO"
// * ✅ ParsedDependencyRelations -> "DependencyRelations"
pub fn parsed_artifact_ref_to_string_test() {
  [
    #("ParsedSLO -> SLO", ast.ParsedSLO, "SLO"),
    #(
      "ParsedDependencyRelations -> DependencyRelations",
      ast.ParsedDependencyRelations,
      "DependencyRelations",
    ),
  ]
  |> test_helpers.table_test_1(ast.parsed_artifact_ref_to_string)
}

// ==== value_to_string ====
// * ✅ TypeValue delegates to parsed_type_to_string
// * ✅ LiteralValue delegates to literal_to_string
pub fn value_to_string_test() {
  [
    #(
      "TypeValue(String) -> String",
      ast.TypeValue(types.ParsedPrimitive(types.String)),
      "String",
    ),
    #(
      "TypeValue(Boolean) -> Boolean",
      ast.TypeValue(types.ParsedPrimitive(types.Boolean)),
      "Boolean",
    ),
    #(
      "LiteralValue(String) -> quoted string",
      ast.LiteralValue(ast.LiteralString("hello")),
      "\"hello\"",
    ),
    #(
      "LiteralValue(Integer) -> number",
      ast.LiteralValue(ast.LiteralInteger(42)),
      "42",
    ),
    #(
      "LiteralValue(True) -> true",
      ast.LiteralValue(ast.LiteralTrue),
      "true",
    ),
  ]
  |> test_helpers.table_test_1(ast.value_to_string)
}
