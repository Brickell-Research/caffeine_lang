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
  common.parse_specification(file_path, dict.new(), fn(doc, _params) {
    common.iteratively_parse_collection(
      glaml.document_root(doc),
      parse_query_template_filter,
      "filters",
    )
  })
}

// ==== Private ====
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
  use accepted_type <- result.try(common.string_to_accepted_type(attribute_type))

  Ok(intermediate_representation.QueryTemplateFilter(
    attribute_name: attribute_name,
    attribute_type: accepted_type,
    required: required,
  ))
}
