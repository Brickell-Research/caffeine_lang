import caffeine_lang_v2/common
import glaml_extended
import gleam/dict
import gleam/result

pub opaque type ServiceExpectation {
  ServiceExpectation(
    name: String,
    blueprint: String,
    inputs: dict.Dict(String, String),
  )
}

pub fn make_service_expectation(
  name name: String,
  blueprint blueprint: String,
  inputs inputs: dict.Dict(String, String),
) -> ServiceExpectation {
  ServiceExpectation(name:, blueprint:, inputs:)
}

pub fn get_name(service_expectation: ServiceExpectation) -> String {
  service_expectation.name
}

pub fn get_blueprint(service_expectation: ServiceExpectation) -> String {
  service_expectation.blueprint
}

pub fn get_inputs(
  service_expectation: ServiceExpectation,
) -> dict.Dict(String, String) {
  service_expectation.inputs
}

/// Parses an expectation invocation file into a list of service expectations.
pub fn parse(file_path: String) -> Result(List(ServiceExpectation), String) {
  use service_expectations <- result.try(common.parse_specification(
    file_path,
    dict.new(),
    parse_service_expectation,
    "expectations",
  ))

  common.validate_uniqueness(
    service_expectations,
    fn(e) { e.name },
    "expectation",
  )
}

fn parse_service_expectation(
  type_node: glaml_extended.Node,
  _params: dict.Dict(String, String),
) -> Result(ServiceExpectation, String) {
  use name <- result.try(glaml_extended.extract_string_from_node(
    type_node,
    "name",
  ))

  use blueprint <- result.try(glaml_extended.extract_string_from_node(
    type_node,
    "blueprint",
  ))

  use inputs <- result.try(glaml_extended.extract_dict_strings_from_node(
    type_node,
    "inputs",
    fail_on_key_duplication: True,
  ))

  Ok(ServiceExpectation(name:, blueprint:, inputs:))
}
