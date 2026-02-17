import gleam/list
import gleam/string

/// Test executor for functions with 1 input.
pub fn array_based_test_executor_1(
  input_expect_pairs: List(#(String, input_type, output_type)),
  test_executor: fn(input_type) -> output_type,
) {
  input_expect_pairs
  |> list.each(fn(tuple) {
    let #(name, input, expected) = tuple
    let result = test_executor(input)
    case result == expected {
      True -> Nil
      False ->
        panic as string.concat([
            "\n\n[",
            name,
            "]\n",
            string.inspect(result),
            "\nshould equal\n",
            string.inspect(expected),
          ])
    }
  })
}
