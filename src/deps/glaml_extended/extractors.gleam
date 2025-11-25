import deps/glaml_extended/yaml
import gleam/dict
import gleam/int
import gleam/list
import gleam/result

/// Extracts a string from a glaml node.
pub fn extract_string_from_node(
  node: yaml.Node,
  key: String,
) -> Result(String, String) {
  use query_template_node <- result.try(case yaml.select_sugar(node, key) {
    Ok(node) -> Ok(node)
    Error(_) -> Error("Missing " <> key)
  })

  case query_template_node {
    yaml.NodeStr(value) -> Ok(value)
    _ -> Error("Expected " <> key <> " to be a string")
  }
}

/// Extracts a float from a glaml node.
/// Also accepts integers and converts them to floats (since YAML/JSON parsers
/// often represent numbers like 99.0 as integers).
pub fn extract_float_from_node(
  node: yaml.Node,
  key: String,
) -> Result(Float, String) {
  use query_template_node <- result.try(case yaml.select_sugar(node, key) {
    Ok(node) -> Ok(node)
    Error(_) -> Error("Missing " <> key)
  })

  case query_template_node {
    yaml.NodeFloat(value) -> Ok(value)
    yaml.NodeInt(value) -> Ok(int.to_float(value))
    _ -> Error("Expected " <> key <> " to be a float")
  }
}

/// Extracts an integer from a glaml node.
pub fn extract_int_from_node(
  node: yaml.Node,
  key: String,
) -> Result(Int, String) {
  use query_template_node <- result.try(case yaml.select_sugar(node, key) {
    Ok(node) -> Ok(node)
    Error(_) -> Error("Missing " <> key)
  })

  case query_template_node {
    yaml.NodeInt(value) -> Ok(value)
    _ -> Error("Expected " <> key <> " to be an integer")
  }
}

/// Extracts a boolean from a glaml node
pub fn extract_bool_from_node(
  node: yaml.Node,
  key: String,
) -> Result(Bool, String) {
  use query_template_node <- result.try(case yaml.select_sugar(node, key) {
    Ok(node) -> Ok(node)
    Error(_) -> Error("Missing " <> key)
  })

  case query_template_node {
    yaml.NodeBool(value) -> Ok(value)
    _ -> Error("Expected " <> key <> " to be a boolean")
  }
}

/// Extracts a list of strings from a glaml node.
pub fn extract_string_list_from_node(
  node: yaml.Node,
  key: String,
) -> Result(List(String), String) {
  use list_node <- result.try(case yaml.select_sugar(node, key) {
    Ok(node) -> Ok(node)
    Error(_) -> Error("Missing " <> key)
  })

  // Try to access the first element to validate it's a list structure
  case yaml.select_sugar(list_node, "#0") {
    Ok(_) -> do_extract_string_list(list_node, 0)
    Error(_) -> {
      // Check if it's a non-list node that would cause the wrong error
      case list_node {
        yaml.NodeStr(_) ->
          Error("Expected " <> key <> " list item to be a string")
        _ -> Error("Expected " <> key <> " to be a list")
      }
    }
  }
}

/// Extracts a dictionary of string key-value pairs from a glaml node.
/// Returns an empty dict if the key is missing (allowing optional empty dicts).
pub fn extract_dict_strings_from_node(
  node: yaml.Node,
  key: String,
) -> Result(dict.Dict(String, String), String) {
  case yaml.select_sugar(node, key) {
    Ok(dict_node) -> {
      case dict_node {
        yaml.NodeMap(entries) -> {
          entries
          |> list.try_map(fn(entry) {
            case entry {
              #(yaml.NodeStr(dict_key), yaml.NodeStr(value)) ->
                Ok(#(dict_key, value))
              _ ->
                Error(
                  "Expected " <> key <> " entries to be string key-value pairs",
                )
            }
          })
          |> result.map(dict.from_list)
        }
        _ -> Error("Expected " <> key <> " to be a map")
      }
    }
    Error(_) -> {
      // If the key is missing, return an empty dict (allows optional empty instantiation)
      Ok(dict.new())
    }
  }
}

/// Iteratively parses a collection of nodes.
pub fn iteratively_parse_collection(
  root: yaml.Node,
  params: dict.Dict(String, String),
  actual_parse_fn: fn(yaml.Node, dict.Dict(String, String)) -> Result(a, String),
  key: String,
) -> Result(List(a), String) {
  use services_node <- result.try(
    yaml.select_sugar(root, key)
    |> result.map_error(fn(_) { "Missing " <> key }),
  )

  do_parse_collection(services_node, 0, params, actual_parse_fn)
}

/// Internal parser for list of nodes, iterates over the list.
fn do_parse_collection(
  services: yaml.Node,
  index: Int,
  params: dict.Dict(String, String),
  actual_parse_fn: fn(yaml.Node, dict.Dict(String, String)) -> Result(a, String),
) -> Result(List(a), String) {
  case yaml.select_sugar(services, "#" <> int.to_string(index)) {
    Ok(service_node) -> {
      use service <- result.try(actual_parse_fn(service_node, params))
      use rest <- result.try(do_parse_collection(
        services,
        index + 1,
        params,
        actual_parse_fn,
      ))
      Ok([service, ..rest])
    }
    // TODO: fix this super hacky way of iterating over SLOs.
    Error(_) -> Ok([])
  }
}

/// Internal helper for extracting string lists from glaml nodes.
fn do_extract_string_list(
  list_node: yaml.Node,
  index: Int,
) -> Result(List(String), String) {
  case yaml.select_sugar(list_node, "#" <> int.to_string(index)) {
    Ok(item_node) -> {
      case item_node {
        yaml.NodeStr(value) -> {
          use rest <- result.try(do_extract_string_list(list_node, index + 1))
          Ok([value, ..rest])
        }
        _ -> Error("Expected list item to be a string")
      }
    }
    Error(_) -> Ok([])
  }
}
