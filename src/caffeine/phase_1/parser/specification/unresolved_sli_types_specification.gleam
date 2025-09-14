import caffeine/phase_1/parser/utils/common
import caffeine/types/specification_types.{
  type SliTypeUnresolved, SliTypeUnresolved,
}
import glaml
import gleam/dict
import gleam/int
import gleam/result

/// Given a specification file, returns a list of unresolved SLI types.
pub fn parse_sli_types_specification(
  file_path: String,
) -> Result(List(SliTypeUnresolved), String) {
  common.parse_specification(file_path, dict.new(), parse_sli_types_from_doc)
}

fn parse_sli_types_from_doc(
  doc: glaml.Document,
  params: dict.Dict(String, String),
) -> Result(List(SliTypeUnresolved), String) {
  use sli_types <- result.try(parse_sli_types(glaml.document_root(doc), params))

  Ok(sli_types)
}

fn parse_sli_types(
  root: glaml.Node,
  _params: dict.Dict(String, String),
) -> Result(List(SliTypeUnresolved), String) {
  use types_node <- result.try(
    glaml.select_sugar(root, "types")
    |> result.map_error(fn(_) { "Missing types" }),
  )

  do_parse_sli_types(types_node, 0)
}

fn do_parse_sli_types(
  types: glaml.Node,
  index: Int,
) -> Result(List(SliTypeUnresolved), String) {
  case glaml.select_sugar(types, "#" <> int.to_string(index)) {
    Ok(type_node) -> {
      use sli_type <- result.try(parse_sli_type(type_node))
      use rest <- result.try(do_parse_sli_types(types, index + 1))
      Ok([sli_type, ..rest])
    }
    // TODO: fix this super hacky way of iterating over SLI types.
    Error(_) -> Ok([])
  }
}

fn parse_sli_type(type_node: glaml.Node) -> Result(SliTypeUnresolved, String) {
  use name <- result.try(common.extract_string_from_node(type_node, "name"))
  use query_template_type <- result.try(common.extract_string_from_node(
    type_node,
    "query_template_type",
  ))

  Ok(SliTypeUnresolved(name: name, query_template_type: query_template_type))
}
