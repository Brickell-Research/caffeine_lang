import caffeine/phase_1/parser/utils/general_common
import caffeine/phase_1/parser/utils/glaml_helpers
import caffeine/types/intermediate_representation
import glaml
import gleam/dict
import gleam/result

// ==== Public ====
/// Given a specification file, returns a list of query template filters.
pub fn parse_query_template_filters_specification(
  file_path: String,
) -> Result(List(intermediate_representation.QueryTemplateFilter), String) {
  glaml_helpers.parse_specification(
    file_path,
    dict.new(),
    parse_query_template_filter,
    "filters",
  )
}

// ==== Private ====
/// Parses a single query template filter.
fn parse_query_template_filter(
  filter: glaml.Node,
  _params: dict.Dict(String, String),
) -> Result(intermediate_representation.QueryTemplateFilter, String) {
  use attribute_name <- result.try(glaml_helpers.extract_string_from_node(
    filter,
    "attribute_name",
  ))
  use attribute_type <- result.try(glaml_helpers.extract_string_from_node(
    filter,
    "attribute_type",
  ))
  use required <- result.try(glaml_helpers.extract_bool_from_node(
    filter,
    "required",
  ))
  use accepted_type <- result.try(general_common.string_to_accepted_type(
    attribute_type,
  ))

  Ok(intermediate_representation.QueryTemplateFilter(
    attribute_name: attribute_name,
    attribute_type: accepted_type,
    required: required,
  ))
}
