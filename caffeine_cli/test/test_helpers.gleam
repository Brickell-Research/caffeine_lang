import gleam/list
import gleam/string

/// Table-driven test executor for functions with 1 input.
pub fn table_test_1(
  cases: List(#(String, input_type, output_type)),
  test_fn: fn(input_type) -> output_type,
) {
  cases
  |> list.each(fn(tuple) {
    let #(name, input, expected) = tuple
    let result = test_fn(input)
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
