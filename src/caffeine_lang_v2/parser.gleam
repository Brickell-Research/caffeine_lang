import caffeine_lang/phase_1/parser/utils/general_common
import deps/glaml_extended/extractors as glaml_extended_helpers
import deps/glaml_extended/yaml
import gleam/dict
import gleam/list
import gleam/result

/// A blueprint is a named collection of inputs, queries, and a value.
///
/// blueprints:
///   - name: success_rate_graphql
///     inputs:
///       gql_operation: String
///     queries:
///       numerator:   'sum.app.requests{operation:${gql_operation},status:info}.as_count()'
///       denominator: 'sum.app.requests{operation:${gql_operation}}.as_count()'
///     value: "numerator / denominator"
///   - name: success_rate_http
///     inputs:
///       endpoint: String
///       status_codes: List(String)
///       environment: String
///     queries:
///       numerator:   'sum.app.requests{endpoint:${endpoint},status:${status_codes},environment:${environment}}.as_count()'
///       denominator: 'sum.app.requests{endpoint:${endpoint,environment:${environment}}.as_count()'
///     value: "numerator / denominator"
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

/// A basic type is an attribute name and a type.
pub type BasicType {
  BasicType(attribute_name: String, attribute_type: AcceptedTypes)
}

// ==== Public ====
/// Parses a blueprint specification file into a list of blueprints.
pub fn parse_blueprint_specification(
  file_path: String,
) -> Result(List(Blueprint), String) {
  general_common.parse_specification(
    file_path,
    dict.new(),
    parse_blueprint,
    "blueprints",
  )
}

// ==== Private ====
/// Parses a single unresolved SLI type.
fn parse_blueprint(
  type_node: yaml.Node,
  _params: dict.Dict(String, String),
) -> Result(Blueprint, String) {
  use name <- result.try(glaml_extended_helpers.extract_string_from_node(
    type_node,
    "name",
  ))
  use inputs <- result.try(
    glaml_extended_helpers.extract_dict_strings_from_node(type_node, "inputs"),
  )

  use queries <- result.try(
    glaml_extended_helpers.extract_dict_strings_from_node(type_node, "queries"),
  )
  use value <- result.try(glaml_extended_helpers.extract_string_from_node(
    type_node,
    "value",
  ))

  use foo <- result.try(dict_strings_to_basic_types(inputs))

  Ok(Blueprint(name: name, inputs: foo, queries: queries, value: value))
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
