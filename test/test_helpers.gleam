/// TODO: very interested in figuring out if we could collapse these to a single executor function.
import caffeine_lang/constants
import gleam/list
import gleam/result
import gleam/string
import simplifile

/// Reads a generator corpus file and canonicalizes Terraform formatting/version text.
pub fn read_generator_corpus(file_name: String) -> String {
  let path = "test/caffeine_lang/corpus/generator/" <> file_name <> ".tf"
  let assert Ok(content) = simplifile.read(path)
  normalize_terraform(content)
}

/// Canonicalizes Terraform formatting and version text so tests stay stable.
pub fn normalize_terraform(terraform: String) -> String {
  terraform
  |> string.replace(constants.version, "{{VERSION}}")
  |> string.replace(version_slug(), "{{VERSION_SLUG}}")
  |> collapse_spaces_before_equals
}

fn version_slug() -> String {
  "v" <> string.replace(constants.version, ".", "")
}

fn collapse_spaces_before_equals(terraform: String) -> String {
  let next = string.replace(terraform, "  =", " =")
  case next == terraform {
    True -> terraform
    False -> collapse_spaces_before_equals(next)
  }
}

pub fn normalize_terraform_result(
  value: Result(String, error),
) -> Result(String, error) {
  value |> result.map(normalize_terraform)
}

pub fn normalize_terraform_result_with_warnings(
  value: Result(#(String, List(String)), error),
) -> Result(#(String, List(String)), error) {
  value
  |> result.map(fn(pair) {
    let #(terraform, warnings) = pair
    #(normalize_terraform(terraform), warnings)
  })
}

pub fn terraform_contains(terraform: String, substring: String) -> Bool {
  string.contains(
    normalize_terraform(terraform),
    normalize_terraform(substring),
  )
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
