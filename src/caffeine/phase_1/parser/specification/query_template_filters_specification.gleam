import caffeine/phase_1/parser/utils/general_common
import caffeine/phase_1/parser/utils/glaml_helpers
import caffeine/types/ast
import glaml
import gleam/dict
import gleam/result

// ==== Public ====
/// Given a specification file, returns a list of query template filters.
pub fn parse_query_template_filters_specification(
  file_path: String,
) -> Result(List(ast.QueryTemplateFilter), String) {
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
) -> Result(ast.QueryTemplateFilter, String) {
  use attribute_name <- result.try(glaml_helpers.extract_string_from_node(
    filter,
    "attribute_name",
  ))
  use attribute_type <- result.try(glaml_helpers.extract_string_from_node(
    filter,
    "attribute_type",
  ))
  use accepted_type <- result.try(general_common.string_to_accepted_type(
    attribute_type,
  ))

  Ok(ast.QueryTemplateFilter(
    attribute_name: attribute_name,
    attribute_type: accepted_type,
  ))
}
