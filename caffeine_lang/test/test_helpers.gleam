/// TODO: very interested in figuring out if we could collapse these to a single executor function.
import caffeine_lang/constants
import gleam/list
import gleam/string
import simplifile

/// Reads a corpus file from the generator test directory, replacing the version placeholder.
pub fn read_generator_corpus(file_name: String) -> String {
  let path = "test/caffeine_lang/corpus/generator/" <> file_name <> ".tf"
  let assert Ok(content) = simplifile.read(path)
  string.replace(content, "{{VERSION}}", constants.version)
}

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

/// Table-driven test executor for functions with 2 inputs.
pub fn table_test_2(
  cases: List(#(String, input1, input2, output_type)),
  test_fn: fn(input1, input2) -> output_type,
) {
  cases
  |> list.each(fn(tuple) {
    let #(name, i1, i2, expected) = tuple
    let result = test_fn(i1, i2)
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

/// Table-driven test executor for functions with 3 inputs.
pub fn table_test_3(
  cases: List(#(String, input1, input2, input3, output_type)),
  test_fn: fn(input1, input2, input3) -> output_type,
) {
  cases
  |> list.each(fn(tuple) {
    let #(name, i1, i2, i3, expected) = tuple
    let result = test_fn(i1, i2, i3)
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
