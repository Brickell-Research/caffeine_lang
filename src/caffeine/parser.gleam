import caffeine/intermediate_representation
import glaml
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub fn parse_instantiation(
  file_path: String,
) -> Result(List(intermediate_representation.Team), String) {
  // get the team name and service name from the file path
  let splitted_file_path = file_path |> string.split("/")
  assert list.length(splitted_file_path) == 4

  // these are fine
  let assert Ok(team_name) = splitted_file_path |> list.drop(2) |> list.first
  let assert Ok(doc) = glaml.parse_file(file_path)

  // Handle empty documents
  case doc {
    [] -> {
      let team =
        intermediate_representation.Team(
          name: "badass_" <> team_name <> "_team",
          slos: [],
        )
      Ok([team])
    }
    _ -> {
      // Normal processing for non-empty documents
      let first_doc = case doc |> list.first {
        Ok(node) -> glaml.document_root(node)
        _ -> panic as "error"
      }

      use slos_node <- result.try(
        glaml.select_sugar(first_doc, "slos")
        |> result.map_error(fn(_) { "Missing SLOs" }),
      )
      use slos <- result.try(parse_slos(slos_node))

      let team =
        intermediate_representation.Team(
          name: "badass_" <> team_name <> "_team",
          slos: slos,
        )
      Ok([team])
    }
  }
}

fn parse_slos(
  slos: glaml.Node,
) -> Result(List(intermediate_representation.Slo), String) {
  parse_slos_iterative(slos, 0, "super_scalabale_web_service")
}

fn parse_slos_iterative(
  slos: glaml.Node,
  index: Int,
  service_name: String,
) -> Result(List(intermediate_representation.Slo), String) {
  case glaml.select_sugar(slos, "#" <> int.to_string(index)) {
    Ok(slo_node) -> {
      use slo <- result.try(parse_slo(slo_node, service_name))
      use rest <- result.try(parse_slos_iterative(slos, index + 1, service_name))
      Ok([slo, ..rest])
    }
    // TODO: fix this super hacky way of iterating over SLOs.
    Error(_) -> Ok([])
  }
}

fn parse_slo(
  slo: glaml.Node,
  service_name: String,
) -> Result(intermediate_representation.Slo, String) {
  use sli_type <- result.try(extract_sli_type(slo))
  use filters <- result.try(extract_filters(slo))
  use threshold <- result.try(extract_threshold(slo))

  Ok(intermediate_representation.Slo(
    sli_type: sli_type,
    filters: filters,
    threshold: threshold,
    service_name: service_name,
  ))
}

fn extract_sli_type(slo: glaml.Node) -> Result(String, String) {
  case glaml.select_sugar(slo, "sli_type") {
    Ok(glaml.NodeStr(value)) -> Ok(value)
    Ok(_) -> Error("Expected sli_type to be a string")
    Error(_) -> Error("Missing sli_type")
  }
}

fn extract_filters(slo: glaml.Node) -> Result(dict.Dict(String, String), String) {
  case glaml.select_sugar(slo, "filters") {
    Ok(glaml.NodeMap(filter_entries)) -> {
      let filters =
        filter_entries
        |> list.map(fn(entry) {
          case entry {
            #(glaml.NodeStr(key), glaml.NodeStr(value)) -> #(key, value)
            _ -> panic as "Expected filter entries to be string pairs"
          }
        })
        |> dict.from_list
      Ok(filters)
    }
    Ok(_) -> Error("Expected filters to be a map")
    Error(_) -> Error("Missing filters")
  }
}

fn extract_threshold(slo: glaml.Node) -> Result(Float, String) {
  case glaml.select_sugar(slo, "threshold") {
    Ok(glaml.NodeFloat(value)) -> Ok(value)
    Ok(_) -> Error("Expected threshold to be a float")
    Error(_) -> Error("Missing threshold")
  }
}
