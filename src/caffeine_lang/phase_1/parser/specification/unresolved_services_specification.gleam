import caffeine_lang/phase_1/parser/unresolved_service
import caffeine_lang/phase_1/parser/utils/general_common
import deps/glaml_extended/extractors as glaml_extended_helpers
import deps/glaml_extended/yaml
import gleam/dict
import gleam/result

// ==== Public ====
/// Given a specification file, returns a list of unresolved service specifications.
pub fn parse_unresolved_services_specification(
  file_path: String,
) -> Result(List(unresolved_service.Service), String) {
  general_common.parse_specification(
    file_path,
    dict.new(),
    parse_service,
    "services",
  )
}

// ==== Private ====
/// Parses a single unresolved service.
fn parse_service(
  service: yaml.Node,
  _params: dict.Dict(String, String),
) -> Result(unresolved_service.Service, String) {
  use sli_types <- result.try(
    glaml_extended_helpers.extract_string_list_from_node(service, "sli_types"),
  )
  use name <- result.try(glaml_extended_helpers.extract_string_from_node(
    service,
    "name",
  ))

  Ok(unresolved_service.Service(name: name, sli_types: sli_types))
}
