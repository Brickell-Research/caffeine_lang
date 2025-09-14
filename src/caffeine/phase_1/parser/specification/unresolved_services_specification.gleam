import caffeine/phase_1/parser/utils/common
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
  common.parse_specification(file_path, dict.new(), parse_services_from_doc)
}

// ==== Private ====
/// Given a document, returns a list of unresolved services.
fn parse_services_from_doc(
  doc: glaml.Document,
  _params: dict.Dict(String, String),
) -> Result(List(ServiceUnresolved), String) {
  use services <- result.try(common.iteratively_parse_collection(
    glaml.document_root(doc),
    parse_service,
    "services",
  ))

  Ok(services)
}

/// Parses a single unresolved service.
fn parse_service(service: glaml.Node) -> Result(ServiceUnresolved, String) {
  use sli_types <- result.try(common.extract_string_list_from_node(
    service,
    "sli_types",
  ))
  use name <- result.try(common.extract_string_from_node(service, "name"))

  Ok(ServiceUnresolved(name: name, sli_types: sli_types))
}
