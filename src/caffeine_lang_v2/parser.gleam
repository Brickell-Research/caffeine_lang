import caffeine_lang_v2/common
import glaml_extended
import gleam/dict
import gleam/list
import gleam/result
import gleam/set
import gleam/string

pub type ServiceExpectation {
  ServiceExpectation(
    name: String,
    blueprint: String,
    inputs: dict.Dict(String, String),
    threshold: Float,
    window_in_days: Int,
  )
}

pub type Blueprint {
  Blueprint(
    name: String,
    inputs: dict.Dict(String, AcceptedTypes),
    queries: dict.Dict(String, String),
    value: String,
  )
}

/// AcceptedTypes is a union of all the types that can be used as filters. It is recursive
/// to allow for nested filters. This may be a bug in the future since it seems it may
/// infinitely recurse.
pub type AcceptedTypes {
  Boolean
  Decimal
  Integer
  String
  NonEmptyList(AcceptedTypes)
  Optional(AcceptedTypes)
}

// ==== Public ====
/// Parses a blueprint specification file into a list of blueprints.
pub fn parse_blueprint_specification(
  file_path: String,
) -> Result(List(Blueprint), String) {
  use blueprints <- result.try(common.parse_specification(
    file_path,
    dict.new(),
    parse_blueprint,
    "blueprints",
  ))

  validate_required_uniqueness_checks_blueprints(blueprints)
}

/// Parses an expectation invocation file into a list of service expectations.
pub fn parse_service_expectation_invocation(
  file_path: String,
) -> Result(List(ServiceExpectation), String) {
  use service_expectations <- result.try(common.parse_specification(
    file_path,
    dict.new(),
    parse_service_expectation,
    "expectations",
  ))

  validate_required_uniqueness_checks_expectations(service_expectations)
}

// ==== Private ====
/// 
fn validate_required_uniqueness_checks_blueprints(
  blueprints: List(Blueprint),
) -> Result(List(Blueprint), String) {
  let duplicate_names = find_duplicates(list.map(blueprints, fn(b) { b.name }))

  case duplicate_names {
    [] -> Ok(blueprints)
    _ ->
      Error(
        "Duplicate blueprint names detected: "
        <> string.join(duplicate_names, ", "),
      )
  }
}

fn validate_required_uniqueness_checks_expectations(
  blueprints: List(ServiceExpectation),
) -> Result(List(ServiceExpectation), String) {
  let duplicate_names = find_duplicates(list.map(blueprints, fn(b) { b.name }))

  case duplicate_names {
    [] -> Ok(blueprints)
    _ ->
      Error(
        "Duplicate blueprint names detected: "
        <> string.join(duplicate_names, ", "),
      )
  }
}

fn find_duplicates(items: List(String)) -> List(String) {
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

fn parse_blueprint(
  type_node: glaml_extended.Node,
  _params: dict.Dict(String, String),
) -> Result(Blueprint, String) {
  use name <- result.try(glaml_extended.extract_string_from_node(
    type_node,
    "name",
  ))

  // inputs and queries are optional, default to empty dict if missing
  // but still error on type mismatches
  use inputs <- result.try(glaml_extended.extract_dict_strings_from_node(
    type_node,
    "inputs",
    fail_on_key_duplication: True,
  ))

  use queries <- result.try(glaml_extended.extract_dict_strings_from_node(
    type_node,
    "queries",
    fail_on_key_duplication: True,
  ))

  use value <- result.try(glaml_extended.extract_string_from_node(
    type_node,
    "value",
  ))

  use inputs_with_accepted_types <- result.try(dict_strings_to_basic_types(
    inputs,
  ))

  Ok(Blueprint(name:, inputs: inputs_with_accepted_types, queries:, value:))
}

fn dict_strings_to_basic_types(
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

fn parse_accepted_type(raw_accepted_type) -> Result(AcceptedTypes, String) {
  case raw_accepted_type {
    "Boolean" -> Ok(Boolean)
    "Decimal" -> Ok(Decimal)
    "Integer" -> Ok(Integer)
    "String" -> Ok(String)
    "NonEmptyList(String)" -> Ok(NonEmptyList(String))
    "NonEmptyList(Integer)" -> Ok(NonEmptyList(Integer))
    "NonEmptyList(Boolean)" -> Ok(NonEmptyList(Boolean))
    "NonEmptyList(Decimal)" -> Ok(NonEmptyList(Decimal))
    "Optional(String)" -> Ok(Optional(String))
    "Optional(Integer)" -> Ok(Optional(Integer))
    "Optional(Boolean)" -> Ok(Optional(Boolean))
    "Optional(Decimal)" -> Ok(Optional(Decimal))
    "Optional(NonEmptyList(String))" -> Ok(Optional(NonEmptyList(String)))
    "Optional(NonEmptyList(Integer))" -> Ok(Optional(NonEmptyList(Integer)))
    "Optional(NonEmptyList(Boolean))" -> Ok(Optional(NonEmptyList(Boolean)))
    "Optional(NonEmptyList(Decimal))" -> Ok(Optional(NonEmptyList(Decimal)))
    _ -> Error("Invalid type: " <> raw_accepted_type)
  }
}

fn parse_service_expectation(
  type_node: glaml_extended.Node,
  _params: dict.Dict(String, String),
) -> Result(ServiceExpectation, String) {
  use name <- result.try(glaml_extended.extract_string_from_node(
    type_node,
    "name",
  ))

  use blueprint <- result.try(glaml_extended.extract_string_from_node(
    type_node,
    "blueprint",
  ))

  // inputs is optional, default to empty dict if missing
  // but still error on type mismatches
  use inputs <- result.try(glaml_extended.extract_dict_strings_from_node(
    type_node,
    "inputs",
    fail_on_key_duplication: True,
  ))

  use threshold <- result.try(glaml_extended.extract_float_from_node(
    type_node,
    "threshold",
  ))
  use window_in_days <- result.try(glaml_extended.extract_int_from_node(
    type_node,
    "window_in_days",
  ))

  Ok(ServiceExpectation(name:, blueprint:, inputs:, threshold:, window_in_days:))
}
