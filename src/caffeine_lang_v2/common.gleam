import glaml_extended
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/set
import gleam/string

/// Parses a specification file into a list of glaml documents according to the given parse function.
pub fn parse_specification(
  file_path: String,
  params: dict.Dict(String, String),
  parse_fn: fn(glaml_extended.Node, dict.Dict(String, String)) ->
    Result(a, String),
  key: String,
) -> Result(List(a), String) {
  // TODO: consider enforcing constraints on file path, however for now, unnecessary.

  // parse the YAML file
  use doc <- result.try(
    glaml_extended.parse_file(file_path)
    |> result.map_error(fn(_) { "Failed to parse YAML file: " <> file_path }),
  )
  let parse_fn_two = fn(doc, _params) {
    iteratively_parse_collection(
      glaml_extended.document_root(doc),
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

/// AcceptedTypes is a union of all the types that can be used as filters. It is recursive
/// to allow for nested filters. This may be a bug in the future since it seems it may
/// infinitely recurse.
pub type AcceptedTypes {
  Boolean
  Float
  Integer
  String
  Dict(AcceptedTypes, AcceptedTypes)
  NonEmptyList(AcceptedTypes)
  Optional(AcceptedTypes)
}

/// Parses a raw string into an AcceptedType.
pub fn parse_accepted_type(raw_accepted_type) -> Result(AcceptedTypes, String) {
  case raw_accepted_type {
    // Basic types
    "Boolean" -> Ok(Boolean)
    "Float" -> Ok(Float)
    "Integer" -> Ok(Integer)
    "String" -> Ok(String)
    // Dict types
    "Dict(String, String)" -> Ok(Dict(String, String))
    "Dict(String, Integer)" -> Ok(Dict(String, Integer))
    "Dict(String, Float)" -> Ok(Dict(String, Float))
    "Dict(String, Boolean)" -> Ok(Dict(String, Boolean))
    // NonEmptyList types
    "NonEmptyList(String)" -> Ok(NonEmptyList(String))
    "NonEmptyList(Integer)" -> Ok(NonEmptyList(Integer))
    "NonEmptyList(Boolean)" -> Ok(NonEmptyList(Boolean))
    "NonEmptyList(Float)" -> Ok(NonEmptyList(Float))
    // Optional types
    "Optional(String)" -> Ok(Optional(String))
    "Optional(Integer)" -> Ok(Optional(Integer))
    "Optional(Boolean)" -> Ok(Optional(Boolean))
    "Optional(Float)" -> Ok(Optional(Float))
    // Optional NonEmptyList types
    "Optional(NonEmptyList(String))" -> Ok(Optional(NonEmptyList(String)))
    "Optional(NonEmptyList(Integer))" -> Ok(Optional(NonEmptyList(Integer)))
    "Optional(NonEmptyList(Boolean))" -> Ok(Optional(NonEmptyList(Boolean)))
    "Optional(NonEmptyList(Float))" -> Ok(Optional(NonEmptyList(Float)))
    // Optional Dict types
    "Optional(Dict(String, String))" -> Ok(Optional(Dict(String, String)))
    "Optional(Dict(String, Integer))" -> Ok(Optional(Dict(String, Integer)))
    "Optional(Dict(String, Float))" -> Ok(Optional(Dict(String, Float)))
    "Optional(Dict(String, Boolean))" -> Ok(Optional(Dict(String, Boolean)))
    _ -> Error("Invalid type: " <> raw_accepted_type)
  }
}

/// Converts a dictionary of string key-value pairs to a dictionary with AcceptedTypes values.
pub fn dict_strings_to_accepted_types(
  dict_strings: dict.Dict(String, String),
) -> Result(dict.Dict(String, AcceptedTypes), String) {
  dict_strings
  |> dict.to_list()
  |> list.try_fold(dict.new(), fn(accumulator, pair) {
    let #(attribute, raw_accepted_type) = pair
    use accepted_type <- result.try(parse_accepted_type(raw_accepted_type))

    Ok(dict.insert(accumulator, attribute, accepted_type))
  })
}

/// Finds duplicate items in a list of strings.
pub fn find_duplicates(items: List(String)) -> List(String) {
  let #(_seen, duplicates) =
    list.fold(items, #(set.new(), set.new()), fn(acc, item) {
      let #(seen, duplicates) = acc
      case set.contains(seen, item) {
        True -> #(seen, set.insert(duplicates, item))
        False -> #(set.insert(seen, item), duplicates)
      }
    })

  set.to_list(duplicates)
}

pub fn validate_uniqueness(
  items: List(a),
  value_extractor_fn: fn(a) -> String,
  type_name: String,
) -> Result(List(a), String) {
  let duplicate_names =
    find_duplicates(list.map(items, fn(e) { value_extractor_fn(e) }))

  case duplicate_names {
    [] -> Ok(items)
    _ ->
      Error(
        "Duplicate "
        <> type_name
        <> " names detected: "
        <> string.join(duplicate_names, ", "),
      )
  }
}

/// Iteratively parses a collection of nodes.
pub fn iteratively_parse_collection(
  root: glaml_extended.Node,
  params: dict.Dict(String, String),
  actual_parse_fn: fn(glaml_extended.Node, dict.Dict(String, String)) ->
    Result(a, String),
  key: String,
) -> Result(List(a), String) {
  use services_node <- result.try(
    glaml_extended.select_sugar(root, key)
    |> result.map_error(fn(_) { "Missing " <> key }),
  )
  do_parse_collection(services_node, 0, params, actual_parse_fn, key)
}

/// Internal parser for list of nodes, iterates over the list.
fn do_parse_collection(
  services: glaml_extended.Node,
  index: Int,
  params: dict.Dict(String, String),
  actual_parse_fn: fn(glaml_extended.Node, dict.Dict(String, String)) ->
    Result(a, String),
  key: String,
) -> Result(List(a), String) {
  case glaml_extended.select_sugar(services, "#" <> int.to_string(index)) {
    Ok(service_node) -> {
      use service <- result.try(actual_parse_fn(service_node, params))
      use rest <- result.try(do_parse_collection(
        services,
        index + 1,
        params,
        actual_parse_fn,
        key,
      ))
      Ok([service, ..rest])
    }
    Error(error) -> {
      case error, index {
        glaml_extended.NodeNotFound(_), 0 -> Error(key <> " is empty")
        glaml_extended.NodeNotFound(_), _ -> Ok([])
        glaml_extended.SelectorParseError, _ -> Error(key <> " is unparsable")
      }
    }
    // TODO: fix this super hacky way of iterating over SLOs.
    // Error(_) -> Ok([])
  }
}
