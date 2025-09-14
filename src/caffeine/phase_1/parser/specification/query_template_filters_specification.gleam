import caffeine/phase_1/parser/utils/common
import caffeine/types/intermediate_representation
import glaml
import gleam/dict
import gleam/result

// ==== Public ====
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

// ==== Private ====
/// Given a document, returns a list of query template filters.
fn parse_query_template_filters_from_doc(
  doc: glaml.Document,
  _params: dict.Dict(String, String),
) -> Result(List(intermediate_representation.QueryTemplateFilter), String) {
  use query_template_filters <- result.try(common.iteratively_parse_collection(
    glaml.document_root(doc),
    parse_query_template_filter,
    "filters",
  ))

  Ok(query_template_filters)
}

/// Parses a single query template filter.
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
  use required <- result.try(common.extract_bool_from_node(filter, "required"))

  let accepted_type_for_attribute_type =
    common.string_to_accepted_type(attribute_type)

  use accepted_type <- result.try(accepted_type_for_attribute_type)

  Ok(intermediate_representation.QueryTemplateFilter(
    attribute_name: attribute_name,
    attribute_type: accepted_type,
    required: required,
  ))
}
