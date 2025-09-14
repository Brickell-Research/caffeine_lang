import caffeine/phase_1/parser/utils/common
import caffeine/types/specification_types.{
  type SliTypeUnresolved, SliTypeUnresolved,
}
import glaml
import gleam/dict
import gleam/result

// ==== Public ====
/// Given a specification file, returns a list of unresolved SLI types.
pub fn parse_unresolved_sli_types_specification(
  file_path: String,
) -> Result(List(SliTypeUnresolved), String) {
  common.parse_specification(file_path, dict.new(), parse_sli_types_from_doc)
}

// ==== Private ====
/// Given a document, returns a list of unresolved SLI types.
fn parse_sli_types_from_doc(
  doc: glaml.Document,
  _params: dict.Dict(String, String),
) -> Result(List(SliTypeUnresolved), String) {
  use sli_types <- result.try(common.iteratively_parse_collection(
    glaml.document_root(doc),
    parse_sli_type,
    "types",
  ))

  Ok(sli_types)
}

/// Parses a single unresolved SLI type.
fn parse_sli_type(type_node: glaml.Node) -> Result(SliTypeUnresolved, String) {
  use name <- result.try(common.extract_string_from_node(type_node, "name"))
  use query_template_type <- result.try(common.extract_string_from_node(
    type_node,
    "query_template_type",
  ))

  Ok(SliTypeUnresolved(name: name, query_template_type: query_template_type))
}
