import caffeine/phase_1/parser/utils/common
import caffeine/types/intermediate_representation
import glaml
import gleam/dict
import gleam/int
import gleam/result

/// Given a specification file, returns a list of query template filters.
pub fn parse_query_template_filters_specification(
  file_path: String,
) -> Result(List(intermediate_representation.QueryTemplateFilter), String) {
  common.parse_specification(
    file_path,
    dict.new(),
    parse_query_template_filters_from_doc,
  )
}

fn parse_query_template_filters_from_doc(
  doc: glaml.Document,
  params: dict.Dict(String, String),
) -> Result(List(intermediate_representation.QueryTemplateFilter), String) {
  use query_template_filters <- result.try(parse_query_template_filters(
    glaml.document_root(doc),
    params,
  ))

  Ok(query_template_filters)
}

fn parse_query_template_filters(
  root: glaml.Node,
  _params: dict.Dict(String, String),
) -> Result(List(intermediate_representation.QueryTemplateFilter), String) {
  use filters_node <- result.try(
    glaml.select_sugar(root, "filters")
    |> result.map_error(fn(_) { "Missing query_template_filters" }),
  )

  do_parse_query_template_filters(filters_node, 0)
}

fn do_parse_query_template_filters(
  filters: glaml.Node,
  index: Int,
) -> Result(List(intermediate_representation.QueryTemplateFilter), String) {
  case glaml.select_sugar(filters, "#" <> int.to_string(index)) {
    Ok(filter_node) -> {
      use filter <- result.try(parse_query_template_filter(filter_node))
      use rest <- result.try(do_parse_query_template_filters(filters, index + 1))
      Ok([filter, ..rest])
    }
    // TODO: fix this super hacky way of iterating over query_template_filters.
    Error(_) -> Ok([])
  }
}

fn parse_query_template_filter(
  filter: glaml.Node,
) -> Result(intermediate_representation.QueryTemplateFilter, String) {
  use attribute_name <- result.try(common.extract_string_from_node(
    filter,
    "attribute_name",
  ))
  use attribute_type <- result.try(common.extract_string_from_node(
    filter,
    "attribute_type",
  ))
  use required <- result.try(extract_attribute_required(filter))

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

  Ok(intermediate_representation.QueryTemplateFilter(
    attribute_name: attribute_name,
    attribute_type: accepted_type,
    required: required,
  ))
}

fn extract_attribute_required(filter: glaml.Node) -> Result(Bool, String) {
  use required <- result.try(common.extract_some_node_by_key(filter, "required"))

  case required {
    glaml.NodeBool(value) -> Ok(value)
    _ -> Error("Expected attribute required to be a boolean")
  }
}
