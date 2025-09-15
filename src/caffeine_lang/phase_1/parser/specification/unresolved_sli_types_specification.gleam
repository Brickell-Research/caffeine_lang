import caffeine_lang/phase_1/parser/utils/glaml_helpers
import caffeine_lang/types/specification_types.{
  type SliTypeUnresolved, SliTypeUnresolved,
}
import glaml
import gleam/dict
import gleam/list
import gleam/result

// ==== Public ====
/// Given a specification file, returns a list of unresolved SLI types.
pub fn parse_unresolved_sli_types_specification(
  file_path: String,
) -> Result(List(SliTypeUnresolved), String) {
  glaml_helpers.parse_specification(
    file_path,
    dict.new(),
    parse_sli_type,
    "types",
  )
}

// ==== Private ====
/// Parses a single unresolved SLI type.
fn parse_sli_type(
  type_node: glaml.Node,
  _params: dict.Dict(String, String),
) -> Result(SliTypeUnresolved, String) {
  use name <- result.try(glaml_helpers.extract_string_from_node(
    type_node,
    "name",
  ))
  use query_template_type <- result.try(glaml_helpers.extract_string_from_node(
    type_node,
    "query_template_type",
  ))
  use metric_attributes_list <- result.try(glaml_helpers.extract_string_list_from_node(
    type_node,
    "metric_attributes",
  ))
  use filters <- result.try(glaml_helpers.extract_string_list_from_node(
    type_node,
    "filters",
  ))

  let metric_attributes = 
    metric_attributes_list
    |> list.map(fn(attr) { #(attr, "") })
    |> dict.from_list

  Ok(SliTypeUnresolved(
    name: name,
    query_template_type: query_template_type,
    metric_attributes: metric_attributes,
    filters: filters,
  ))
}
