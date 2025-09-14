import caffeine/phase_1/parser/utils/common
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
  common.parse_specification(file_path, dict.new(), fn(doc, _params) {
    common.iteratively_parse_collection(
      glaml.document_root(doc),
      parse_query_template_type,
      "query_template_types",
    )
  })
}

// ==== Private ====
/// Parses a single unresolved query template type.
fn parse_query_template_type(
  type_node: glaml.Node,
) -> Result(QueryTemplateTypeUnresolved, String) {
  use numerator_query <- result.try(common.extract_string_from_node(
    type_node,
    "numerator_query",
  ))
  use denominator_query <- result.try(common.extract_string_from_node(
    type_node,
    "denominator_query",
  ))
  use filters <- result.try(common.extract_string_list_from_node(
    type_node,
    "filters",
  ))

  Ok(GoodOverBadQueryTemplateUnresolved(
    numerator_query: numerator_query,
    denominator_query: denominator_query,
    filters: filters,
  ))
}
