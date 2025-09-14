import caffeine/phase_1/parser/common
import caffeine/types/intermediate_representation
import caffeine/types/specification_types.{
  type ServiceUnresolved, type SliTypeUnresolved, ServiceUnresolved,
  SliTypeUnresolved,
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

/// Given a specification file, returns a list of SLI filters.
pub fn parse_sli_filters_specification(
  file_path: String,
) -> Result(List(intermediate_representation.SliFilter), String) {
  common.parse_specification(file_path, dict.new(), parse_sli_filters_from_doc)
}

fn parse_sli_filters_from_doc(
  doc: glaml.Document,
  params: dict.Dict(String, String),
) -> Result(List(intermediate_representation.SliFilter), String) {
  use sli_filters <- result.try(parse_sli_filters(
    glaml.document_root(doc),
    params,
  ))

  Ok(sli_filters)
}

fn parse_sli_filters(
  root: glaml.Node,
  _params: dict.Dict(String, String),
) -> Result(List(intermediate_representation.SliFilter), String) {
  use sli_filters_node <- result.try(
    glaml.select_sugar(root, "filters")
    |> result.map_error(fn(_) { "Missing sli_filters" }),
  )

  do_parse_sli_filters(sli_filters_node, 0)
}

fn do_parse_sli_filters(
  sli_filters: glaml.Node,
  index: Int,
) -> Result(List(intermediate_representation.SliFilter), String) {
  case glaml.select_sugar(sli_filters, "#" <> int.to_string(index)) {
    Ok(sli_filter_node) -> {
      use sli_filter <- result.try(parse_sli_filter(sli_filter_node))
      use rest <- result.try(do_parse_sli_filters(sli_filters, index + 1))
      Ok([sli_filter, ..rest])
    }
    // TODO: fix this super hacky way of iterating over sli_filters.
    Error(_) -> Ok([])
  }
}

fn parse_sli_filter(
  sli_filter: glaml.Node,
) -> Result(intermediate_representation.SliFilter, String) {
  use attribute_name <- result.try(common.extract_string_from_node(
    sli_filter,
    "attribute_name",
  ))
  use attribute_type <- result.try(common.extract_string_from_node(
    sli_filter,
    "attribute_type",
  ))
  use required <- result.try(extract_attribute_required(sli_filter))

  let accepted_type_for_attribute_type = case attribute_type {
    "Boolean" -> Ok(intermediate_representation.Boolean)
    "Decimal" -> Ok(intermediate_representation.Decimal)
    "Integer" -> Ok(intermediate_representation.Integer)
    "String" -> Ok(intermediate_representation.String)
    "List(String)" ->
      Ok(intermediate_representation.List(intermediate_representation.String))
    _ -> Error("Unknown attribute type: " <> attribute_type)
  }

  use accepted_type <- result.try(accepted_type_for_attribute_type)

  Ok(intermediate_representation.SliFilter(
    attribute_name: attribute_name,
    attribute_type: accepted_type,
    required: required,
  ))
}

fn extract_attribute_required(sli_filter: glaml.Node) -> Result(Bool, String) {
  use required <- result.try(common.extract_some_node_by_key(
    sli_filter,
    "required",
  ))

  case required {
    glaml.NodeBool(value) -> Ok(value)
    _ -> Error("Expected attribute required to be a string")
  }
}

/// Given a specification file, returns a list of unresolved SLI types.
pub fn parse_sli_types_specification(
  file_path: String,
) -> Result(List(SliTypeUnresolved), String) {
  common.parse_specification(file_path, dict.new(), parse_sli_types_from_doc)
}

fn parse_sli_types_from_doc(
  doc: glaml.Document,
  params: dict.Dict(String, String),
) -> Result(List(SliTypeUnresolved), String) {
  use sli_types <- result.try(parse_sli_types(glaml.document_root(doc), params))

  Ok(sli_types)
}

fn parse_sli_types(
  root: glaml.Node,
  _params: dict.Dict(String, String),
) -> Result(List(SliTypeUnresolved), String) {
  use types_node <- result.try(
    glaml.select_sugar(root, "types")
    |> result.map_error(fn(_) { "Missing types" }),
  )

  do_parse_sli_types(types_node, 0)
}

fn do_parse_sli_types(
  types: glaml.Node,
  index: Int,
) -> Result(List(SliTypeUnresolved), String) {
  case glaml.select_sugar(types, "#" <> int.to_string(index)) {
    Ok(type_node) -> {
      use sli_type <- result.try(parse_sli_type(type_node))
      use rest <- result.try(do_parse_sli_types(types, index + 1))
      Ok([sli_type, ..rest])
    }
    // TODO: fix this super hacky way of iterating over SLI types.
    Error(_) -> Ok([])
  }
}

fn parse_sli_type(type_node: glaml.Node) -> Result(SliTypeUnresolved, String) {
  use name <- result.try(common.extract_string_from_node(type_node, "name"))
  use query_template_type <- result.try(common.extract_string_from_node(
    type_node,
    "query_template_type",
  ))
  use filters <- result.try(extract_sli_type_filters(type_node))

  Ok(SliTypeUnresolved(
    name: name,
    query_template_type: query_template_type,
    filters: filters,
  ))
}

fn extract_sli_type_filters(
  type_node: glaml.Node,
) -> Result(List(String), String) {
  use filters_node <- result.try(common.extract_some_node_by_key(
    type_node,
    "filters",
  ))

  // Try to access the first element to validate it's a list structure
  case glaml.select_sugar(filters_node, "#0") {
    Ok(_) -> do_extract_sli_type_filters(filters_node, 0)
    Error(_) -> {
      // Check if it's a non-list node that would cause the wrong error
      case filters_node {
        glaml.NodeStr(_) -> Error("Expected sli type filter to be a string")
        _ -> Error("Expected filters to be a list")
      }
    }
  }
}

fn do_extract_sli_type_filters(
  filters_node: glaml.Node,
  index: Int,
) -> Result(List(String), String) {
  case glaml.select_sugar(filters_node, "#" <> int.to_string(index)) {
    Ok(filter_node) -> {
      use filter <- result.try(extract_sli_type_filter(filter_node))
      use rest <- result.try(do_extract_sli_type_filters(
        filters_node,
        index + 1,
      ))
      Ok([filter, ..rest])
    }
    Error(_) -> Ok([])
  }
}

fn extract_sli_type_filter(filter_node: glaml.Node) -> Result(String, String) {
  case filter_node {
    glaml.NodeStr(value) -> Ok(value)
    _ -> Error("Expected sli type filter to be a string")
  }
}

/// Given a specification file, returns a list of resolved query template types.
pub fn parse_query_template_types_specification(
  file_path: String,
) -> Result(List(intermediate_representation.QueryTemplateType), String) {
  common.parse_specification(file_path, dict.new(), parse_query_template_types_from_doc)
}

fn parse_query_template_types_from_doc(
  doc: glaml.Document,
  params: dict.Dict(String, String),
) -> Result(List(intermediate_representation.QueryTemplateType), String) {
  use query_template_types <- result.try(parse_query_template_types(glaml.document_root(doc), params))

  Ok(query_template_types)
}

fn parse_query_template_types(
  root: glaml.Node,
  _params: dict.Dict(String, String),
) -> Result(List(intermediate_representation.QueryTemplateType), String) {
  use types_node <- result.try(
    glaml.select_sugar(root, "query_template_types")
    |> result.map_error(fn(_) { "Missing query_template_types" }),
  )

  do_parse_query_template_types(types_node, 0)
}

fn do_parse_query_template_types(
  types: glaml.Node,
  index: Int,
) -> Result(List(intermediate_representation.QueryTemplateType), String) {
  case glaml.select_sugar(types, "#" <> int.to_string(index)) {
    Ok(type_node) -> {
      use query_template_type <- result.try(parse_query_template_type(type_node))
      use rest <- result.try(do_parse_query_template_types(types, index + 1))
      Ok([query_template_type, ..rest])
    }
    // TODO: fix this super hacky way of iterating over query template types.
    Error(_) -> Ok([])
  }
}

fn parse_query_template_type(type_node: glaml.Node) -> Result(intermediate_representation.QueryTemplateType, String) {
  use name <- result.try(common.extract_string_from_node(type_node, "name"))
  use numerator_query <- result.try(common.extract_string_from_node(
    type_node,
    "numerator_query",
  ))
  use denominator_query <- result.try(common.extract_string_from_node(
    type_node,
    "denominator_query",
  ))

  Ok(intermediate_representation.GoodOverBadQueryTemplate(
    name: name,
    numerator_query: numerator_query,
    denominator_query: denominator_query,
  ))
}
