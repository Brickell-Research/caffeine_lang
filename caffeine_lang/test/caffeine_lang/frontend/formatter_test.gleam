import caffeine_lang/frontend/formatter
import gleam/list
import gleeunit/should
import simplifile

// ==== Helpers ====
fn corpus_path(file_name: String) -> String {
  "test/caffeine_lang/corpus/frontend/formatter/" <> file_name <> ".caffeine"
}

fn read_file(path: String) -> String {
  let assert Ok(content) = simplifile.read(path)
  content
}

// ==== format ====
// * ✅ formats unformatted blueprint to canonical output
// * ✅ formats unformatted expects to canonical output
// * ✅ already-formatted blueprint is unchanged
// * ✅ already-formatted expects is unchanged
// * ✅ type alias formatted correctly
// * ✅ complex types formatted correctly
pub fn format_test() {
  [
    #("unformatted_blueprint", "formatted_blueprint"),
    #("unformatted_expects", "formatted_expects"),
    #("already_formatted", "already_formatted"),
    #("formatted_expects", "formatted_expects"),
    #("type_alias_blueprint", "type_alias_blueprint"),
    #("complex_types", "complex_types"),
  ]
  |> list.each(fn(pair) {
    let #(input_name, expected_name) = pair
    let input = read_file(corpus_path(input_name))
    let expected = read_file(corpus_path(expected_name))
    let assert Ok(result) = formatter.format(input)
    result |> should.equal(expected)
  })
}

// ==== format (idempotency) ====
// * ✅ format(format(blueprint)) == format(blueprint)
// * ✅ format(format(expects)) == format(expects)
pub fn format_idempotent_test() {
  ["unformatted_blueprint", "unformatted_expects"]
  |> list.each(fn(file_name) {
    let input = read_file(corpus_path(file_name))
    let assert Ok(first) = formatter.format(input)
    let assert Ok(second) = formatter.format(first)
    second |> should.equal(first)
  })
}

// ==== format (errors) ====
// * ✅ invalid source returns error
pub fn format_invalid_source_test() {
  formatter.format("this is not valid caffeine")
  |> should.be_error()
}
