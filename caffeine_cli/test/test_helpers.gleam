import gleam/list
import gleeunit/should

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
