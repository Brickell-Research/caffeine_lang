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
      // Empty YAML file, return team with no SLOs
      let team =
        intermediate_representation.Team(
          name: "badass_" <> team_name <> "_team",
          slos: [],
        )
      Ok([team])
    }
    _ -> {
      // Normal processing for non-empty documents
      let first_doc = case { doc |> list.first } {
        Ok(node) -> {
          glaml.document_root(node)
        }
        _ -> panic as "error"
      }

      let parsed_slos = case { glaml.select_sugar(first_doc, "slos") } {
        Ok(slos) -> {
          parse_slos(slos)
        }
        _ -> {
          Error("Missing SLOs")
        }
      }

      case parsed_slos {
        Ok(slos) -> {
          // Create the team with parsed SLOs
          let team =
            intermediate_representation.Team(
              name: "badass_" <> team_name <> "_team",
              // The test expects "badass_platform_team" for "platform"
              slos: slos,
            )
          Ok([team])
        }
        Error(e) -> {
          Error(e)
        }
      }
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
      case parse_slo(slo_node, service_name) {
        Ok(slo) -> {
          case parse_slos_iterative(slos, index + 1, service_name) {
            Ok(rest) -> Ok([slo, ..rest])
            Error(e) -> Error(e)
          }
        }
        Error(e) -> Error(e)
      }
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
  case { glaml.select_sugar(slo, "sli_type") } {
    Ok(node) -> {
      try_extract_text(node)
    }
    _ -> {
      Error("Missing sli_type")
    }
  }
}

fn extract_filters(slo: glaml.Node) -> Result(dict.Dict(String, String), String) {
  case glaml.select_sugar(slo, "filters") {
    Ok(filters_node) -> {
      case filters_node {
        glaml.NodeMap(filter_entries) -> {
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
        _ -> Error("Expected filters to be a map")
      }
    }
    Error(_) -> Error("Missing filters")
  }
}

fn extract_threshold(slo: glaml.Node) -> Result(Float, String) {
  case { glaml.select_sugar(slo, "threshold") } {
    Ok(threshold_node) -> {
      try_extract_float(threshold_node)
    }
    _ -> {
      Error("Missing threshold")
    }
  }
}

fn try_extract_text(node: glaml.Node) -> Result(String, String) {
  case node {
    glaml.NodeStr(value) -> Ok(value)
    _ -> Error("Expected node to be a string")
  }
}

fn try_extract_float(node: glaml.Node) -> Result(Float, String) {
  case node {
    glaml.NodeFloat(value) -> Ok(value)
    _ -> Error("Expected node to be a float")
  }
}
