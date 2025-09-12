import caffeine/intermediate_representation
import glaml
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub fn parse_instantiation(
  file_path: String,
) -> Result(List(intermediate_representation.Team), String) {
  let splitted_file_path = file_path |> string.split("/")

  use <- bool.guard(
    list.length(splitted_file_path) != 4,
    Error("Invalid file path: expected format 'dir/dir/team/file.yaml'"),
  )

  use team_name <- result.try(
    splitted_file_path
    |> list.drop(2)
    |> list.first
    |> result.replace_error("Failed to extract team name from path"),
  )

  use service_name <- result.try(
    splitted_file_path
    |> list.last
    |> result.map(fn(name) { string.replace(name, ".yaml", "") })
    |> result.replace_error("Failed to extract service name from path"),
  )

  use doc <- result.try(
    glaml.parse_file(file_path)
    |> result.map_error(fn(_) { "Failed to parse YAML file: " <> file_path }),
  )

  // Handle empty documents
  case doc {
    [] -> Error("Empty YAML file")
    [first, ..] -> {
      let root = glaml.document_root(first)

      use slos_node <- result.try(
        glaml.select_sugar(root, "slos")
        |> result.map_error(fn(_) { "Missing SLOs" }),
      )

      use slos <- result.try(parse_slos(slos_node, service_name))

      Ok([intermediate_representation.Team(name: team_name, slos: slos)])
    }
  }
}

fn parse_slos(
  slos: glaml.Node,
  service_name: String,
) -> Result(List(intermediate_representation.Slo), String) {
  parse_slos_iterative(slos, 0, service_name)
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
