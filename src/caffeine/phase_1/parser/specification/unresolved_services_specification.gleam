import caffeine/phase_1/parser/utils/glaml_helpers
import caffeine/types/specification_types.{
  type ServiceUnresolved, ServiceUnresolved,
}
import glaml
import gleam/dict
import gleam/result

// ==== Public ====
/// Given a specification file, returns a list of unresolved service specifications.
pub fn parse_unresolved_services_specification(
  file_path: String,
) -> Result(List(specification_types.ServiceUnresolved), String) {
  glaml_helpers.parse_specification(
    file_path,
    dict.new(),
    parse_service,
    "services",
  )
}

// ==== Private ====
/// Parses a single unresolved service.
fn parse_service(
  service: glaml.Node,
  _params: dict.Dict(String, String),
) -> Result(ServiceUnresolved, String) {
  use sli_types <- result.try(glaml_helpers.extract_string_list_from_node(
    service,
    "sli_types",
  ))
  use name <- result.try(glaml_helpers.extract_string_from_node(service, "name"))

  Ok(ServiceUnresolved(name: name, sli_types: sli_types))
}
