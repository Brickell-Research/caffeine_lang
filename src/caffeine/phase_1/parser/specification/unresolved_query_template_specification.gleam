import caffeine/phase_1/parser/utils/common
import caffeine/types/specification_types.{
  type QueryTemplateTypeUnresolved, GoodOverBadQueryTemplateUnresolved,
}
import glaml
import gleam/dict
import gleam/int
import gleam/result

/// Given a specification file, returns a list of resolved query template types.
pub fn parse_query_template_types_specification(
  file_path: String,
) -> Result(List(QueryTemplateTypeUnresolved), String) {
  common.parse_specification(
    file_path,
    dict.new(),
    parse_query_template_types_from_doc,
  )
}

fn parse_query_template_types_from_doc(
  doc: glaml.Document,
  params: dict.Dict(String, String),
) -> Result(List(QueryTemplateTypeUnresolved), String) {
  use query_template_types <- result.try(parse_query_template_types(
    glaml.document_root(doc),
    params,
  ))

  Ok(query_template_types)
}

fn parse_query_template_types(
  root: glaml.Node,
  _params: dict.Dict(String, String),
) -> Result(List(QueryTemplateTypeUnresolved), String) {
  use types_node <- result.try(
    glaml.select_sugar(root, "query_template_types")
    |> result.map_error(fn(_) { "Missing query_template_types" }),
  )

  do_parse_query_template_types(types_node, 0)
}

fn do_parse_query_template_types(
  types: glaml.Node,
  index: Int,
) -> Result(List(QueryTemplateTypeUnresolved), String) {
  case glaml.select_sugar(types, "#" <> int.to_string(index)) {
    Ok(type_node) -> {
      use query_template_type <- result.try(parse_query_template_type(type_node))
      use rest <- result.try(do_parse_query_template_types(types, index + 1))
      Ok([query_template_type, ..rest])
    }
    // TODO: fix this super hacky way of iterating over query template types.
    Error(_) -> Ok([])
  }
}

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
