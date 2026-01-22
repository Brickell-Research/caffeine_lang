import caffeine_lang/frontend/generator
import caffeine_lang/frontend/parser
import caffeine_lang/frontend/validator
import gleam/json
import gleam/string
import simplifile
import test_helpers

// ==== Helpers ====
fn generator_path(file_name: String) {
  "test/caffeine_lang/corpus/frontend/generator/" <> file_name
}

fn read_file(path: String) -> String {
  let assert Ok(content) = simplifile.read(path)
  content
}

fn parse_and_validate_blueprints(file_name: String) -> json.Json {
  let content = generator_path(file_name <> ".caffeine") |> read_file
  let assert Ok(file) = parser.parse_blueprints_file(content)
  let assert Ok(validated) = validator.validate_blueprints_file(file)
  generator.generate_blueprints_json(validated)
}

fn parse_and_validate_expects(file_name: String) -> json.Json {
  let content = generator_path(file_name <> ".caffeine") |> read_file
  let assert Ok(file) = parser.parse_expects_file(content)
  let assert Ok(validated) = validator.validate_expects_file(file)
  generator.generate_expects_json(validated)
}

fn expected_json(file_name: String) -> String {
  generator_path(file_name <> ".json") |> read_file
}

fn strip_whitespace(s: String) -> String {
  s
  |> string.replace(" ", "")
  |> string.replace("\n", "")
  |> string.replace("\t", "")
}

// ==== generate_blueprints_json ====
// * ✅ simple blueprint
// * ✅ multi-artifact blueprint
// * ✅ blueprint with extends (extendable flattening)
// * ✅ blueprint with extends override (later values win)
// * ✅ advanced types (List, Dict, Optional, Defaulted, OneOf, Range)
// * ✅ template variable transformation (${} -> $$$$)
// * ✅ type alias resolution (inlines type aliases in output)
pub fn generate_blueprints_json_test() {
  [
    #("blueprints_simple", strip_whitespace(expected_json("blueprints_simple"))),
    #(
      "blueprints_multi_artifact",
      strip_whitespace(expected_json("blueprints_multi_artifact")),
    ),
    #(
      "blueprints_with_extends",
      strip_whitespace(expected_json("blueprints_with_extends")),
    ),
    #(
      "blueprints_extends_override",
      strip_whitespace(expected_json("blueprints_extends_override")),
    ),
    #(
      "blueprints_advanced_types",
      strip_whitespace(expected_json("blueprints_advanced_types")),
    ),
    #(
      "blueprints_template_vars",
      strip_whitespace(expected_json("blueprints_template_vars")),
    ),
    #(
      "blueprints_type_alias",
      strip_whitespace(expected_json("blueprints_type_alias")),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(name) {
    let generated = parse_and_validate_blueprints(name)
    strip_whitespace(json.to_string(generated))
  })
}

// ==== generate_expects_json ====
// * ✅ simple expectation
// * ✅ expectation with extends (extendable flattening)
// * ✅ expectation with extends override (later values win)
// * ✅ multiple extends (merge order: left to right, then item)
// * ✅ complex literals (lists, nested structs, booleans, numbers)
pub fn generate_expects_json_test() {
  [
    #("expects_simple", strip_whitespace(expected_json("expects_simple"))),
    #(
      "expects_with_extends",
      strip_whitespace(expected_json("expects_with_extends")),
    ),
    #(
      "expects_extends_override",
      strip_whitespace(expected_json("expects_extends_override")),
    ),
    #(
      "expects_multiple_extends",
      strip_whitespace(expected_json("expects_multiple_extends")),
    ),
    #(
      "expects_complex_literals",
      strip_whitespace(expected_json("expects_complex_literals")),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(name) {
    let generated = parse_and_validate_expects(name)
    strip_whitespace(json.to_string(generated))
  })
}
