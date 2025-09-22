import caffeine_lang/cql/parser.{parse_expr}
import caffeine_lang/phase_1/parser/utils/glaml_helpers
import caffeine_lang/types/unresolved/unresolved_query_template_type
import glaml
import gleam/dict
import gleam/result

// ==== Public ====
/// Given a specification file, returns a list of unresolved query template types.
pub fn parse_unresolved_query_template_types_specification(
  file_path: String,
) -> Result(List(unresolved_query_template_type.QueryTemplateType), String) {
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
) -> Result(unresolved_query_template_type.QueryTemplateType, String) {
  use name <- result.try(glaml_helpers.extract_string_from_node(
    type_node,
    "name",
  ))
  use specification_of_query_templates <- result.try(
    glaml_helpers.extract_string_list_from_node(
      type_node,
      "specification_of_query_templates",
    ),
  )

  use query_string <- result.try(glaml_helpers.extract_string_from_node(
    type_node,
    "query",
  ))

  use query <- result.try(parse_expr(query_string))

  Ok(unresolved_query_template_type.QueryTemplateType(
    name: name,
    specification_of_query_templates: specification_of_query_templates,
    query: query,
  ))
}
