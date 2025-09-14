import caffeine/phase_1/parser/utils/common
import caffeine/types/specification_types.{
  type ServiceUnresolved, ServiceUnresolved,
}
import glaml
import gleam/dict
import gleam/int
import gleam/result

/// Given a specification file, returns a list of unresolved service specifications.
pub fn parse_services_specification(
  file_path: String,
) -> Result(List(specification_types.ServiceUnresolved), String) {
  common.parse_specification(file_path, dict.new(), parse_services_from_doc)
}

fn parse_services_from_doc(
  doc: glaml.Document,
  params: dict.Dict(String, String),
) -> Result(List(ServiceUnresolved), String) {
  use services <- result.try(parse_services(glaml.document_root(doc), params))

  Ok(services)
}

fn parse_services(
  root: glaml.Node,
  _params: dict.Dict(String, String),
) -> Result(List(ServiceUnresolved), String) {
  use services_node <- result.try(
    glaml.select_sugar(root, "services")
    |> result.map_error(fn(_) { "Missing services" }),
  )

  do_parse_services(services_node, 0)
}

fn do_parse_services(
  services: glaml.Node,
  index: Int,
) -> Result(List(ServiceUnresolved), String) {
  case glaml.select_sugar(services, "#" <> int.to_string(index)) {
    Ok(service_node) -> {
      use service <- result.try(parse_service(service_node))
      use rest <- result.try(do_parse_services(services, index + 1))
      Ok([service, ..rest])
    }
    // TODO: fix this super hacky way of iterating over SLOs.
    Error(_) -> Ok([])
  }
}

fn parse_service(service: glaml.Node) -> Result(ServiceUnresolved, String) {
  use sli_types <- result.try(extract_sli_types(service))
  use name <- result.try(common.extract_string_from_node(service, "name"))

  Ok(ServiceUnresolved(name: name, sli_types: sli_types))
}

fn extract_sli_types(service: glaml.Node) -> Result(List(String), String) {
  use sli_types_node <- result.try(common.extract_some_node_by_key(
    service,
    "sli_types",
  ))
  do_extract_sli_types(sli_types_node, 0)
}

fn do_extract_sli_types(
  sli_types_node: glaml.Node,
  index: Int,
) -> Result(List(String), String) {
  case glaml.select_sugar(sli_types_node, "#" <> int.to_string(index)) {
    Ok(sli_type_node) -> {
      use sli_type <- result.try(extract_sli_type(sli_type_node))
      use rest <- result.try(do_extract_sli_types(sli_types_node, index + 1))
      Ok([sli_type, ..rest])
    }
    Error(_) -> Ok([])
  }
}

fn extract_sli_type(sli_type_node: glaml.Node) -> Result(String, String) {
  case sli_type_node {
    glaml.NodeStr(value) -> Ok(value)
    _ -> Error("Expected sli type to be a string")
  }
}
