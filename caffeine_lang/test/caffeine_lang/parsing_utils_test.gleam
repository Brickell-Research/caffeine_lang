import caffeine_lang/parsing_utils
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
    #("basic split", "String, Integer", ["String", "Integer"]),
    #("commas inside parens ignored", "Dict(String, Integer), Float", [
      "Dict(String, Integer)",
      "Float",
    ]),
    #("commas inside braces ignored", "String { x | x in { a, b } }, Integer", [
      "String { x | x in { a, b } }",
      "Integer",
    ]),
    #("nested parens and braces", "Dict(String, List(Integer)), Boolean", [
      "Dict(String, List(Integer))",
      "Boolean",
    ]),
    #("empty string", "", []),
    #("single item (no comma)", "String", ["String"]),
  ]
  |> test_helpers.table_test_1(parsing_utils.split_at_top_level_comma)
}

// ==== extract_paren_content ====
// * ✅ happy path - simple parens
// * ✅ nested parens
// * ✅ no parens returns Error
// * ✅ content after closing paren returns Error
pub fn extract_paren_content_test() {
  [
    #("happy path - simple parens", "(String)", Ok("String")),
    #("nested parens", "(Dict(String, Integer))", Ok("Dict(String, Integer)")),
    #("prefix before parens", "List(String)", Ok("String")),
    #("no parens returns Error", "no parens", Error(Nil)),
    #(
      "content after closing paren returns Error",
      "(String) { x | x in { a } }",
      Error(Nil),
    ),
  ]
  |> test_helpers.table_test_1(parsing_utils.extract_paren_content)
}

// ==== paren_innerds_trimmed ====
// * ✅ with parens -> inner content trimmed
// * ✅ without parens -> raw string trimmed
// * ✅ nested parens
pub fn paren_innerds_trimmed_test() {
  [
    #("with parens -> inner content trimmed", "(String)", "String"),
    #("with parens and spaces -> inner content trimmed", "( String )", "String"),
    #("without parens -> raw string trimmed", "  hello  ", "hello"),
    #("nested parens", "(Dict(String, Integer))", "Dict(String, Integer)"),
  ]
  |> test_helpers.table_test_1(parsing_utils.paren_innerds_trimmed)
}

// ==== paren_innerds_split_and_trimmed ====
// * ✅ single arg
// * ✅ multiple args
// * ✅ nested types
// * ✅ no parens -> empty list
pub fn paren_innerds_split_and_trimmed_test() {
  [
    #("single arg", "(String)", ["String"]),
    #("multiple args", "(String, Integer)", ["String", "Integer"]),
    #("nested types", "(String, Dict(String, Integer))", [
      "String",
      "Dict(String, Integer)",
    ]),
    #("no parens -> empty list", "no parens", []),
  ]
  |> test_helpers.table_test_1(parsing_utils.paren_innerds_split_and_trimmed)
}
