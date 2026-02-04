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
// ==== format (comments within blocks) ====
// * ✅ comments within a single blueprint block
// * ✅ comments within a single expects block
// * ✅ comments between fields in struct
// * ✅ trailing comments inside struct
// * ✅ comments in extendable struct
// ==== format (comments between blocks) ====
// * ✅ comments between expects blocks
// * ✅ comments between blueprint blocks
// * ✅ many consecutive comments between expects blocks
// * ✅ multi-block expects with extendable and comments everywhere
// * ✅ multi-block blueprints with comments between blocks
// * ✅ comments between all section types (type alias, extendable, blueprint)
// * ✅ real-world sidekiq multi-block expects with comments
// * ✅ extendable joining collapses blank lines between extendables
pub fn format_test() {
  [
    #("unformatted_blueprint", "formatted_blueprint"),
    #("unformatted_expects", "formatted_expects"),
    #("already_formatted", "already_formatted"),
    #("formatted_expects", "formatted_expects"),
    #("type_alias_blueprint", "type_alias_blueprint"),
    #("complex_types", "complex_types"),
    // Comments within blocks
    #("comments_blueprint", "comments_blueprint"),
    #("comments_expects", "comments_expects"),
    #("comments_in_struct_fields", "comments_in_struct_fields"),
    #("comments_trailing_in_struct", "comments_trailing_in_struct"),
    #("comments_in_extendable_struct", "comments_in_extendable_struct"),
    // Comments between blocks
    #("comments_between_expects_blocks", "comments_between_expects_blocks"),
    #("comments_between_blueprint_blocks", "comments_between_blueprint_blocks"),
    #("comments_many_consecutive", "comments_many_consecutive"),
    #(
      "comments_multi_expects_with_extendable",
      "comments_multi_expects_with_extendable",
    ),
    #("comments_multi_blueprint_blocks", "comments_multi_blueprint_blocks"),
    #(
      "comments_all_section_types_blueprint",
      "comments_all_section_types_blueprint",
    ),
    #("comments_sidekiq_real_world", "comments_sidekiq_real_world"),
    // Extendable joining (blank line between extendables is collapsed)
    #("unformatted_extendable_joining", "formatted_extendable_joining"),
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
// * ✅ format(format(x)) == format(x) for all comment-heavy files
pub fn format_idempotent_test() {
  [
    "unformatted_blueprint",
    "unformatted_expects",
    "comments_blueprint",
    "comments_expects",
    "comments_between_expects_blocks",
    "comments_between_blueprint_blocks",
    "comments_many_consecutive",
    "comments_in_struct_fields",
    "comments_trailing_in_struct",
    "comments_in_extendable_struct",
    "comments_multi_expects_with_extendable",
    "comments_multi_blueprint_blocks",
    "comments_all_section_types_blueprint",
    "comments_sidekiq_real_world",
    "unformatted_extendable_joining",
  ]
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
