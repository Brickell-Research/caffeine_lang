import caffeine_lang_v2/common/helpers
import gleam/dict
import gleam/result
import yay

pub type Expectation {
  Expectation(
    name: String,
    blueprint: String,
    inputs: dict.Dict(String, String),
  )
}

pub fn make_service_expectation(
  name name: String,
  blueprint blueprint: String,
  inputs inputs: dict.Dict(String, String),
) -> Expectation {
  Expectation(name:, blueprint:, inputs:)
}

/// Parses an expectation invocation file into a list of service expectations.
pub fn parse(file_path: String) -> Result(List(Expectation), String) {
  use service_expectations <- result.try(helpers.parse_specification(
    file_path,
    dict.new(),
    parse_service_expectation,
    "expectations",
  ))

  helpers.validate_uniqueness(
    service_expectations,
    fn(e) { e.name },
    "expectation",
  )
}

fn parse_service_expectation(
  type_node: yay.Node,
  _params: dict.Dict(String, String),
) -> Result(Expectation, String) {
  use name <- result.try(
    yay.extract_string(type_node, "name")
    |> result.map_error(fn(extraction_error) {
      yay.extraction_error_to_string(extraction_error)
    }),
  )

  use blueprint <- result.try(
    yay.extract_string(type_node, "blueprint")
    |> result.map_error(fn(extraction_error) {
      yay.extraction_error_to_string(extraction_error)
    }),
  )

  use inputs <- result.try(
    yay.extract_string_map_with_duplicate_detection(
      type_node,
      "inputs",
      fail_on_key_duplication: True,
    )
    |> result.map_error(fn(extraction_error) {
      yay.extraction_error_to_string(extraction_error)
    }),
  )

  Ok(Expectation(name:, blueprint:, inputs:))
}
