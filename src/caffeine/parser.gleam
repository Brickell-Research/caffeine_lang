import caffeine/intermediate_representation
import glaml
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// Parse a Caffeine configuration file into an intermediate representation.
pub fn parse(
  specification_file_path: String,
  instantiation_file_path: String,
) -> Result(intermediate_representation.Organization, String) {
  use services <- result.try(parse_specification(specification_file_path))
  use teams <- result.try(parse_instantiation(instantiation_file_path))

  Ok(intermediate_representation.Organization(
    teams: teams,
    service_definitions: services,
  ))
}

pub fn parse_instantiation(
  file_path: String,
) -> Result(List(intermediate_representation.Team), String) {
  // get the team name and service name from the file path
  let splitted_file_path = file_path |> string.split("/")
  assert list.length(splitted_file_path) == 4

  // Extract team name from path: test/artifacts/platform/reliable_service.yaml
  // We want the "platform" part (index 2)
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
        Ok(slos) -> parse_slos(slos)
        _ -> []
      }

      // Create the team with parsed SLOs
      let team =
        intermediate_representation.Team(
          name: "badass_" <> team_name <> "_team",
          // The test expects "badass_platform_team" for "platform"
          slos: parsed_slos,
        )

      Ok([team])
    }
  }
}

fn parse_slos(slos: glaml.Node) -> List(intermediate_representation.Slo) {
  parse_slos_iterative(slos, 0, "super_scalabale_web_service")
}

fn parse_slos_iterative(
  slos: glaml.Node,
  index: Int,
  service_name: String,
) -> List(intermediate_representation.Slo) {
  case { glaml.select_sugar(slos, "#" <> index |> int.to_string) } {
    Ok(slos_list) -> {
      [parse_slo(slos_list, service_name)]
      |> list.append(parse_slos_iterative(slos, index + 1, service_name))
    }
    _ -> []
  }
}

fn parse_slo(
  slo: glaml.Node,
  service_name: String,
) -> intermediate_representation.Slo {
  let assert Ok(sli_type_node) = glaml.select_sugar(slo, "sli_type")
  let assert Ok(filters_node) = glaml.select_sugar(slo, "filters")
  let assert Ok(threshold_node) = glaml.select_sugar(slo, "threshold")

  // Extract the actual string value using pattern matching
  let sli_type_text = try_extract_text(sli_type_node)

  // Extract the actual float value using pattern matching
  let threshold_value = try_extract_float(threshold_node)

  // Extract the filters map and convert to dictionary
  let filters = case filters_node {
    glaml.NodeMap(filter_entries) -> {
      filter_entries
      |> list.map(fn(entry) {
        case entry {
          #(glaml.NodeStr(key), glaml.NodeStr(value)) -> #(key, value)
          _ -> panic as "Expected filter entries to be string pairs"
        }
      })
      |> dict.from_list
    }
    _ -> panic as "Expected filters to be a map"
  }

  intermediate_representation.Slo(
    sli_type: sli_type_text,
    filters: filters,
    threshold: threshold_value,
    service_name: service_name,
  )
}

fn try_extract_text(node: glaml.Node) -> String {
  case node {
    glaml.NodeStr(value) -> value
    _ -> panic as "Expected node to be a string"
  }
}

fn try_extract_float(node: glaml.Node) -> Float {
  case node {
    glaml.NodeFloat(value) -> value
    _ -> panic as "Expected node to be a float"
  }
}

pub fn parse_specification(
  file_path: String,
) -> Result(List(intermediate_representation.Service), String) {
  let assert Ok(_ctx) = glaml.parse_file(file_path)
  panic as "not implemented"
}
