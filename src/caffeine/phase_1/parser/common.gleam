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
    _ -> Error("Empty YAML file: within apply_to_glaml_document")
  }
}

/// Parses a specification file into a list of glaml documents according to the given parse function.
pub fn parse_specification(
  file_path: String,
  params: dict.Dict(String, String),
  parse_fn: fn(glaml.Document, dict.Dict(String, String)) -> Result(a, String),
) -> Result(a, String) {
  // TODO: consider enforcing constraints on file path, however for now, unnecessary.

  // parse the YAML file
  use doc <- result.try(parse_yaml_file(file_path))

  // parse the intermediate representation, here just the sli_types
  case doc {
    [first, ..] -> parse_fn(first, params)
    _ -> Error("Empty YAML file: " <> file_path)
  }
}

/// Extracts a string from a glaml node.
pub fn extract_string_from_node(
  node: glaml.Node,
  key: String,
) -> Result(String, String) {
  use query_template_node <- result.try(extract_some_node_by_key(node, key))

  case query_template_node {
    glaml.NodeStr(value) -> Ok(value)
    _ -> Error("Expected " <> key <> " to be a string")
  }
}

/// Extracts a float from a glaml node.
pub fn extract_float_from_node(
  node: glaml.Node,
  key: String,
) -> Result(Float, String) {
  use query_template_node <- result.try(extract_some_node_by_key(node, key))

  case query_template_node {
    glaml.NodeFloat(value) -> Ok(value)
    _ -> Error("Expected " <> key <> " to be a float")
  }
}
