import glaml
import gleam/dict
import gleam/list
import gleam/result
import gleam/string

/// Parses a YAML file into a list of glaml documents. This is a helper method for dealing with yaml files.
pub fn parse_yaml_file(
  file_path: String,
) -> Result(List(glaml.Document), String) {
  glaml.parse_file(file_path)
  |> result.map_error(fn(_) { "Failed to parse YAML file: " <> file_path })
}

/// Extracts a node's value by key. This is a helper method for dealing with glaml nodes.
pub fn extract_some_node_by_key(
  slo: glaml.Node,
  key: String,
) -> Result(glaml.Node, String) {
  case glaml.select_sugar(slo, key) {
    Ok(node) -> Ok(node)
    Error(_) -> Error("Missing " <> key)
  }
}

/// Extracts the service and team name from a file path. This is a helper method for dealing with file paths
/// and the specific format we're expecting as per logic to simplify and minimalize the information that actually
/// goes into yaml files.
pub fn extract_service_and_team_name_from_file_path(
  file_path: String,
) -> Result(#(String, String), String) {
  case file_path |> string.split("/") |> list.reverse {
    [file, team, ..] -> Ok(#(team, string.replace(file, ".yaml", "")))
    _ -> Error("Invalid file path: expected at least 'team/service.yaml'")
  }
}

/// Applies a function to a glaml document. This is a helper method for dealing with glaml documents which
/// may have been overkill for a helper method, however we can reuse this between the two parsers we have:
/// (1) instantiation.gleam
/// (2) specification.gleam
pub fn apply_to_glaml_document(
  docs: List(glaml.Document),
  params: dict.Dict(String, String),
  f: fn(glaml.Document, dict.Dict(String, String)) -> Result(value, String),
) -> Result(value, String) {
  case docs {
    [first, ..] -> f(first, params)
    _ -> Error("Empty YAML file")
  }
}
