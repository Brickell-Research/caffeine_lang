import caffeine_lang/phase_1/parser/utils/glaml_helpers
import caffeine_lang/types/unresolved/unresolved_sli_type
import glaml
import gleam/dict
import gleam/result

// ==== Public ====
/// Given a specification file, returns a list of unresolved SLI types.
pub fn parse_unresolved_sli_types_specification(
  file_path: String,
) -> Result(List(unresolved_sli_type.SliType), String) {
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
) -> Result(unresolved_sli_type.SliType, String) {
  use name <- result.try(glaml_helpers.extract_string_from_node(
    type_node,
    "name",
  ))
  use query_template_type <- result.try(glaml_helpers.extract_string_from_node(
    type_node,
    "query_template_type",
  ))
  use typed_instatiation_of_query_templates <- result.try(
    glaml_helpers.extract_dict_strings_from_node(
      type_node,
      "typed_instatiation_of_query_templates",
    ),
  )
  use specification_of_query_templatized_variables <- result.try(
    glaml_helpers.extract_string_list_from_node(
      type_node,
      "specification_of_query_templatized_variables",
    ),
  )

  Ok(unresolved_sli_type.SliType(
    name: name,
    query_template_type: query_template_type,
    typed_instatiation_of_query_templates: typed_instatiation_of_query_templates,
    specification_of_query_templatized_variables: specification_of_query_templatized_variables,
  ))
}
