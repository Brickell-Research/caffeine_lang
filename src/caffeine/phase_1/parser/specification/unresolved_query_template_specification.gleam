import caffeine/phase_1/parser/utils/glaml_helpers
import caffeine/types/specification_types.{
  type QueryTemplateTypeUnresolved, GoodOverBadQueryTemplateUnresolved,
}
import glaml
import gleam/dict
import gleam/result

// ==== Public ====
/// Given a specification file, returns a list of unresolved query template types.
pub fn parse_unresolved_query_template_types_specification(
  file_path: String,
) -> Result(List(QueryTemplateTypeUnresolved), String) {
  glaml_helpers.parse_specification(
    file_path,
    dict.new(),
    parse_query_template_type,
    "query_template_types",
  )
}

// ==== Private ====
/// Parses a single unresolved query template type.
fn parse_query_template_type(
  type_node: glaml.Node,
  _params: dict.Dict(String, String),
) -> Result(QueryTemplateTypeUnresolved, String) {
  use numerator_query <- result.try(glaml_helpers.extract_string_from_node(
    type_node,
    "numerator_query",
  ))
  use denominator_query <- result.try(glaml_helpers.extract_string_from_node(
    type_node,
    "denominator_query",
  ))
  use filters <- result.try(glaml_helpers.extract_string_list_from_node(
    type_node,
    "filters",
  ))

  Ok(GoodOverBadQueryTemplateUnresolved(
    numerator_query: numerator_query,
    denominator_query: denominator_query,
    filters: filters,
  ))
}
