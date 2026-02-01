import caffeine_lang/common/parsing_utils
import test_helpers

// ==== split_at_top_level_comma ====
// * ✅ basic split
// * ✅ commas inside parens ignored
// * ✅ commas inside braces ignored
// * ✅ nested parens and braces
// * ✅ empty string
// * ✅ single item (no comma)
pub fn split_at_top_level_comma_test() {
  [
    #("String, Integer", ["String", "Integer"]),
    #("Dict(String, Integer), Float", ["Dict(String, Integer)", "Float"]),
    #("String { x | x in { a, b } }, Integer", [
      "String { x | x in { a, b } }",
      "Integer",
    ]),
    #("Dict(String, List(Integer)), Boolean", [
      "Dict(String, List(Integer))",
      "Boolean",
    ]),
    #("", []),
    #("String", ["String"]),
  ]
  |> test_helpers.array_based_test_executor_1(
    parsing_utils.split_at_top_level_comma,
  )
}

// ==== extract_paren_content ====
// * ✅ happy path - simple parens
// * ✅ nested parens
// * ✅ no parens returns Error
// * ✅ content after closing paren returns Error
pub fn extract_paren_content_test() {
  [
    #("(String)", Ok("String")),
    #("(Dict(String, Integer))", Ok("Dict(String, Integer)")),
    #("List(String)", Ok("String")),
    #("no parens", Error(Nil)),
    #("(String) { x | x in { a } }", Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(
    parsing_utils.extract_paren_content,
  )
}

// ==== paren_innerds_trimmed ====
// * ✅ with parens -> inner content trimmed
// * ✅ without parens -> raw string trimmed
// * ✅ nested parens
pub fn paren_innerds_trimmed_test() {
  [
    #("(String)", "String"),
    #("( String )", "String"),
    #("  hello  ", "hello"),
    #("(Dict(String, Integer))", "Dict(String, Integer)"),
  ]
  |> test_helpers.array_based_test_executor_1(
    parsing_utils.paren_innerds_trimmed,
  )
}

// ==== paren_innerds_split_and_trimmed ====
// * ✅ single arg
// * ✅ multiple args
// * ✅ nested types
// * ✅ no parens -> empty list
pub fn paren_innerds_split_and_trimmed_test() {
  [
    #("(String)", ["String"]),
    #("(String, Integer)", ["String", "Integer"]),
    #("(String, Dict(String, Integer))", ["String", "Dict(String, Integer)"]),
    #("no parens", []),
  ]
  |> test_helpers.array_based_test_executor_1(
    parsing_utils.paren_innerds_split_and_trimmed,
  )
}
