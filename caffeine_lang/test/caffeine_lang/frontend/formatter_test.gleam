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
// * ✅ formats unformatted measurement to canonical output
// * ✅ formats unformatted expects to canonical output
// * ✅ already-formatted measurement is unchanged
// * ✅ already-formatted expects is unchanged
// * ✅ type alias formatted correctly
// * ✅ complex types formatted correctly
// ==== format (comments within blocks) ====
// * ✅ comments within a single measurement block
// * ✅ comments within a single expects block
// * ✅ comments between fields in struct
// * ✅ trailing comments inside struct
// * ✅ trailing comments inside literal struct
// * ✅ comments in extendable struct
// ==== format (comments between blocks) ====
// * ✅ comments between expects blocks
// * ✅ comments between measurement blocks
// * ✅ many consecutive comments between expects blocks
// * ✅ multi-block expects with extendable and comments everywhere
// * ✅ multi-block measurements with comments between blocks
// * ✅ comments between all section types (type alias, extendable, measurement)
// * ✅ real-world sidekiq multi-block expects with comments
// * ✅ extendable joining collapses blank lines between extendables
// * ✅ record type measurement formats correctly
// * ✅ percentage types and literals format correctly
// ==== format (80-column boundary) ====
// * ✅ inline struct at 65 chars stays inline (65 + 14 = 79 < 80)
// * ✅ multiline struct at 66 chars goes multiline (66 + 14 = 80, not < 80)
// ==== format (empty struct with comment) ====
// * ✅ empty extendable struct with trailing comment preserves comment
pub fn format_test() {
  [
    #("unformatted_measurement", "formatted_measurement"),
    #("unformatted_expects", "formatted_expects"),
    #("already_formatted", "already_formatted"),
    #("formatted_expects", "formatted_expects"),
    #("type_alias_measurement", "type_alias_measurement"),
    #("complex_types", "complex_types"),
    // Comments within blocks
    #("comments_measurement", "comments_measurement"),
    #("comments_expects", "comments_expects"),
    #("comments_in_struct_fields", "comments_in_struct_fields"),
    #("comments_trailing_in_struct", "comments_trailing_in_struct"),
    #(
      "comments_trailing_in_literal_struct",
      "comments_trailing_in_literal_struct",
    ),
    #("comments_in_extendable_struct", "comments_in_extendable_struct"),
    // Comments between blocks
    #("comments_between_expects_blocks", "comments_between_expects_blocks"),
    #(
      "comments_between_measurement_blocks",
      "comments_between_measurement_blocks",
    ),
    #("comments_many_consecutive", "comments_many_consecutive"),
    #(
      "comments_multi_expects_with_extendable",
      "comments_multi_expects_with_extendable",
    ),
    #("comments_multi_measurement_blocks", "comments_multi_measurement_blocks"),
    #(
      "comments_all_section_types_measurement",
      "comments_all_section_types_measurement",
    ),
    #("comments_sidekiq_real_world", "comments_sidekiq_real_world"),
    // Extendable joining (blank line between extendables is collapsed)
    #("unformatted_extendable_joining", "formatted_extendable_joining"),
    // Record types
    #("record_type_measurement", "record_type_measurement"),
    // Percentage types
    #("percentage_types", "percentage_types"),
    // 80-column boundary
    #("boundary_80_col", "boundary_80_col"),
    // Empty struct with trailing comment
    #("empty_struct_trailing_comment", "empty_struct_trailing_comment"),
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
    "unformatted_measurement",
    "unformatted_expects",
    "comments_measurement",
    "comments_expects",
    "comments_between_expects_blocks",
    "comments_between_measurement_blocks",
    "comments_many_consecutive",
    "comments_in_struct_fields",
    "comments_trailing_in_struct",
    "comments_trailing_in_literal_struct",
    "comments_in_extendable_struct",
    "comments_multi_expects_with_extendable",
    "comments_multi_measurement_blocks",
    "comments_all_section_types_measurement",
    "comments_sidekiq_real_world",
    "unformatted_extendable_joining",
    "record_type_measurement",
    "percentage_types",
    "boundary_80_col",
    "empty_struct_trailing_comment",
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
