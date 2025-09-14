import caffeine/phase_1/parser/utils/general_common
import caffeine/phase_1/parser/utils/glaml_helpers
import caffeine/types/intermediate_representation
import glaml
import gleam/dict
import gleam/int
import gleam/list
import gleam/result

// ==== Public ====
/// Parses an instantiation from a YAML file. This is a single team with at least one slo.
/// Note that within a configutation repository, there can be multiple instantiations for
/// the same team and even the same service. Logic for this lives within the linking code.
pub fn parse_team_instantiation(
  file_path: String,
) -> Result(intermediate_representation.Team, String) {
  use params <- result.try(extract_params_from_file_path(file_path))

  glaml_helpers.parse_specification(file_path, params, parse_instantiation_from_doc)
}

// ==== Private ====
/// Extracts team and service name parameters from the file path.
fn extract_params_from_file_path(
  file_path: String,
) -> Result(dict.Dict(String, String), String) {
  use #(team_name, service_name) <- result.try(
    general_common.extract_service_and_team_name_from_file_path(file_path),
  )
  let params =
    dict.from_list([#("team_name", team_name), #("service_name", service_name)])

  Ok(params)
}

/// Given a document, returns a team instantiation.
fn parse_instantiation_from_doc(
  doc: glaml.Document,
  params: dict.Dict(String, String),
) -> Result(intermediate_representation.Team, String) {
  // these assertions are ok because we already extracted the service and team name from the file path
  // above and would not have gotten here if we didn't have them.
  let assert Ok(service_name) = dict.get(params, "service_name")
  let assert Ok(team_name) = dict.get(params, "team_name")

  // TODO: figure out how to refactor to use common.iteratively_parse_collection
  use slos <- result.try(parse_slos(glaml.document_root(doc), service_name))

  Ok(intermediate_representation.Team(name: team_name, slos: slos))
}

/// Top level parser for list of SLOs.
fn parse_slos(
  root: glaml.Node,
  service_name: String,
) -> Result(List(intermediate_representation.Slo), String) {
  use slos_node <- result.try(
    glaml.select_sugar(root, "slos")
    |> result.map_error(fn(_) { "Missing SLOs" }),
  )

  do_parse_slos(slos_node, 0, service_name)
}

/// Internal parser for list of SLOs, iterates over the list.
fn do_parse_slos(
  slos: glaml.Node,
  index: Int,
  service_name: String,
) -> Result(List(intermediate_representation.Slo), String) {
  case glaml.select_sugar(slos, "#" <> int.to_string(index)) {
    Ok(slo_node) -> {
      use slo <- result.try(parse_slo(slo_node, service_name))
      use rest <- result.try(do_parse_slos(slos, index + 1, service_name))
      Ok([slo, ..rest])
    }
    // TODO: fix this super hacky way of iterating over SLOs.
    Error(_) -> Ok([])
  }
}

/// Parses a single SLO.
fn parse_slo(
  slo: glaml.Node,
  service_name: String,
) -> Result(intermediate_representation.Slo, String) {
  use sli_type <- result.try(glaml_helpers.extract_string_from_node(slo, "sli_type"))
  use filters <- result.try(extract_filters(slo))
  use threshold <- result.try(glaml_helpers.extract_float_from_node(slo, "threshold"))

  Ok(intermediate_representation.Slo(
    sli_type:,
    filters:,
    threshold:,
    service_name:,
  ))
}

/// Extracts filters from an SLO node as a dictionary of key-value pairs.
fn extract_filters(slo: glaml.Node) -> Result(dict.Dict(String, String), String) {
  use filters_node <- result.try(glaml_helpers.extract_some_node_by_key(slo, "filters"))

  case filters_node {
    glaml.NodeMap(entries) -> {
      entries
      |> list.try_map(fn(entry) {
        case entry {
          #(glaml.NodeStr(key), glaml.NodeStr(value)) -> Ok(#(key, value))
          _ -> Error("Filter entries must be string key-value pairs")
        }
      })
      |> result.map(dict.from_list)
    }
    _ -> Error("Expected filters to be a map")
  }
}
