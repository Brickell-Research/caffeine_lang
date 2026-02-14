/// TODO: very interested in figuring out if we could collapse these to a single executor function.
import caffeine_lang/constants
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

/// Reads a corpus file from the generator test directory, replacing the version placeholder.
pub fn read_generator_corpus(file_name: String) -> String {
  let path = "test/caffeine_lang/corpus/generator/" <> file_name <> ".tf"
  let assert Ok(content) = simplifile.read(path)
  string.replace(content, "{{VERSION}}", constants.version)
}

/// Test executor for functions with 1 input
pub fn array_based_test_executor_1(
  input_expect_pairs: List(#(input_type, output_type)),
  test_executor: fn(input_type) -> output_type,
) {
  input_expect_pairs
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    test_executor(input) |> should.equal(expected)
  })
}

/// Test executor for functions with 2 inputs
pub fn array_based_test_executor_2(
  input_expect_pairs: List(#(input1, input2, output_type)),
  test_executor: fn(input1, input2) -> output_type,
) {
  input_expect_pairs
  |> list.each(fn(tuple) {
    let #(i1, i2, expected) = tuple
    test_executor(i1, i2) |> should.equal(expected)
  })
}

/// Test executor for functions with 3 inputs
pub fn array_based_test_executor_3(
  input_expect_pairs: List(#(input1, input2, input3, output_type)),
  test_executor: fn(input1, input2, input3) -> output_type,
) {
  input_expect_pairs
  |> list.each(fn(tuple) {
    let #(i1, i2, i3, expected) = tuple
    test_executor(i1, i2, i3) |> should.equal(expected)
  })
}
