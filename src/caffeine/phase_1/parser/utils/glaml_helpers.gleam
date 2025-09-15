import glaml
import gleam/dict
import gleam/int
import gleam/list
import gleam/result

// ==== Public ====

/// Parses a specification file into a list of glaml documents according to the given parse function.
pub fn parse_specification(
  file_path: String,
  params: dict.Dict(String, String),
  parse_fn: fn(glaml.Node, dict.Dict(String, String)) -> Result(a, String),
  key: String,
) -> Result(List(a), String) {
  // TODO: consider enforcing constraints on file path, however for now, unnecessary.

  // parse the YAML file
  use doc <- result.try(
    glaml.parse_file(file_path)
    |> result.map_error(fn(_) { "Failed to parse YAML file: " <> file_path }),
  )

  let parse_fn_two = fn(doc, _params) {
    iteratively_parse_collection(
      glaml.document_root(doc),
      params,
      parse_fn,
      key,
    )
  }

  // parse the intermediate representation, here just the sli_types
  case doc {
    [first, ..] -> parse_fn_two(first, params)
    _ -> Error("Empty YAML file: " <> file_path)
  }
}

/// Extracts a string from a glaml node.
pub fn extract_string_from_node(
  node: glaml.Node,
  key: String,
) -> Result(String, String) {
  use query_template_node <- result.try(case glaml.select_sugar(node, key) {
    Ok(node) -> Ok(node)
    Error(_) -> Error("Missing " <> key)
  })

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
  use query_template_node <- result.try(case glaml.select_sugar(node, key) {
    Ok(node) -> Ok(node)
    Error(_) -> Error("Missing " <> key)
  })

  case query_template_node {
    glaml.NodeFloat(value) -> Ok(value)
    _ -> Error("Expected " <> key <> " to be a float")
  }
}

/// Extracts an integer from a glaml node.
pub fn extract_int_from_node(
  node: glaml.Node,
  key: String,
) -> Result(Int, String) {
  use query_template_node <- result.try(case glaml.select_sugar(node, key) {
    Ok(node) -> Ok(node)
    Error(_) -> Error("Missing " <> key)
  })

  case query_template_node {
    glaml.NodeInt(value) -> Ok(value)
    _ -> Error("Expected " <> key <> " to be an integer")
  }
}

/// Extracts a boolean from a glaml node
pub fn extract_bool_from_node(
  node: glaml.Node,
  key: String,
) -> Result(Bool, String) {
  use query_template_node <- result.try(case glaml.select_sugar(node, key) {
    Ok(node) -> Ok(node)
    Error(_) -> Error("Missing " <> key)
  })

  case query_template_node {
    glaml.NodeBool(value) -> Ok(value)
    _ -> Error("Expected " <> key <> " to be a boolean")
  }
}

/// Extracts a list of strings from a glaml node.
pub fn extract_string_list_from_node(
  node: glaml.Node,
  key: String,
) -> Result(List(String), String) {
  use list_node <- result.try(case glaml.select_sugar(node, key) {
    Ok(node) -> Ok(node)
    Error(_) -> Error("Missing " <> key)
  })

  // Try to access the first element to validate it's a list structure
  case glaml.select_sugar(list_node, "#0") {
    Ok(_) -> do_extract_string_list(list_node, 0)
    Error(_) -> {
      // Check if it's a non-list node that would cause the wrong error
      case list_node {
        glaml.NodeStr(_) ->
          Error("Expected " <> key <> " list item to be a string")
        _ -> Error("Expected " <> key <> " to be a list")
      }
    }
  }
}

/// Extracts a dictionary of string key-value pairs from a glaml node.
pub fn extract_dict_strings_from_node(
  node: glaml.Node,
  key: String,
) -> Result(dict.Dict(String, String), String) {
  use dict_node <- result.try(case glaml.select_sugar(node, key) {
    Ok(node) -> Ok(node)
    Error(_) -> Error("Missing " <> key)
  })

  case dict_node {
    glaml.NodeMap(entries) -> {
      entries
      |> list.try_map(fn(entry) {
        case entry {
          #(glaml.NodeStr(dict_key), glaml.NodeStr(value)) ->
            Ok(#(dict_key, value))
          _ ->
            Error("Expected " <> key <> " entries to be string key-value pairs")
        }
      })
      |> result.map(dict.from_list)
    }
    _ -> Error("Expected " <> key <> " to be a map")
  }
}

// ==== Private ====
/// Iteratively parses a collection of nodes.
fn iteratively_parse_collection(
  root: glaml.Node,
  params: dict.Dict(String, String),
  actual_parse_fn: fn(glaml.Node, dict.Dict(String, String)) ->
    Result(a, String),
  key: String,
) -> Result(List(a), String) {
  use services_node <- result.try(
    glaml.select_sugar(root, key)
    |> result.map_error(fn(_) { "Missing " <> key }),
  )

  do_parse_collection(services_node, 0, params, actual_parse_fn)
}

/// Internal parser for list of nodes, iterates over the list.
fn do_parse_collection(
  services: glaml.Node,
  index: Int,
  params: dict.Dict(String, String),
  actual_parse_fn: fn(glaml.Node, dict.Dict(String, String)) ->
    Result(a, String),
) -> Result(List(a), String) {
  case glaml.select_sugar(services, "#" <> int.to_string(index)) {
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
  list_node: glaml.Node,
  index: Int,
) -> Result(List(String), String) {
  case glaml.select_sugar(list_node, "#" <> int.to_string(index)) {
    Ok(item_node) -> {
      case item_node {
        glaml.NodeStr(value) -> {
          use rest <- result.try(do_extract_string_list(list_node, index + 1))
          Ok([value, ..rest])
        }
        _ -> Error("Expected list item to be a string")
      }
    }
    Error(_) -> Ok([])
  }
}
