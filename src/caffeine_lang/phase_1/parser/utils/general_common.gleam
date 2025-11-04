import caffeine_lang/types/common/accepted_types
import glaml
import glaml_extended/extractors as glaml_extended_helpers
import gleam/dict
import gleam/list
import gleam/result
import gleam/string

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
    glaml_extended_helpers.iteratively_parse_collection(
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

/// Converts a string to an accepted type.
pub fn string_to_accepted_type(
  string_val: String,
) -> Result(accepted_types.AcceptedTypes, String) {
  case string_val {
    "String" -> Ok(accepted_types.String)
    "Integer" -> Ok(accepted_types.Integer)
    "Boolean" -> Ok(accepted_types.Boolean)
    "Decimal" -> Ok(accepted_types.Decimal)
    "NonEmptyList(String)" ->
      Ok(accepted_types.NonEmptyList(accepted_types.String))
    "NonEmptyList(Integer)" ->
      Ok(accepted_types.NonEmptyList(accepted_types.Integer))
    "NonEmptyList(Boolean)" ->
      Ok(accepted_types.NonEmptyList(accepted_types.Boolean))
    "NonEmptyList(Decimal)" ->
      Ok(accepted_types.NonEmptyList(accepted_types.Decimal))
    "Optional(String)" -> Ok(accepted_types.Optional(accepted_types.String))
    "Optional(Integer)" -> Ok(accepted_types.Optional(accepted_types.Integer))
    "Optional(Boolean)" -> Ok(accepted_types.Optional(accepted_types.Boolean))
    "Optional(Decimal)" -> Ok(accepted_types.Optional(accepted_types.Decimal))
    "Optional(NonEmptyList(String))" ->
      Ok(
        accepted_types.Optional(accepted_types.NonEmptyList(
          accepted_types.String,
        )),
      )
    "Optional(NonEmptyList(Integer))" ->
      Ok(
        accepted_types.Optional(accepted_types.NonEmptyList(
          accepted_types.Integer,
        )),
      )
    "Optional(NonEmptyList(Boolean))" ->
      Ok(
        accepted_types.Optional(accepted_types.NonEmptyList(
          accepted_types.Boolean,
        )),
      )
    "Optional(NonEmptyList(Decimal))" ->
      Ok(
        accepted_types.Optional(accepted_types.NonEmptyList(
          accepted_types.Decimal,
        )),
      )
    _ -> {
      case string.starts_with(string_val, "List(List(") {
        True ->
          Error(
            "Only one level of recursion is allowed for lists: " <> string_val,
          )
        False ->
          case string.starts_with(string_val, "Optional(List(List(") {
            True ->
              Error(
                "Only one level of recursion is allowed for lists, even in optional: "
                <> string_val,
              )
            False ->
              Error(
                "Unknown attribute type: "
                <> string_val
                <> ". Supported: String, Integer, Boolean, Decimal, NonEmptyList(String), NonEmptyList(Integer), NonEmptyList(Boolean), NonEmptyList(Decimal), Optional(String), Optional(Integer), Optional(Boolean), Optional(Decimal), Optional(NonEmptyList(String)), Optional(NonEmptyList(Integer)), Optional(NonEmptyList(Boolean)), Optional(NonEmptyList(Decimal))",
              )
          }
      }
    }
  }
}

/// Extracts team and service name parameters from the file path.
pub fn extract_params_from_file_path(
  file_path: String,
) -> Result(dict.Dict(String, String), String) {
  use #(team_name, service_name) <- result.try(
    case file_path |> string.split("/") |> list.reverse {
      [file, team, ..] -> Ok(#(team, string.replace(file, ".yaml", "")))
      _ -> Error("Invalid file path: expected at least 'team/service.yaml'")
    },
  )
  let params =
    dict.from_list([#("team_name", team_name), #("service_name", service_name)])

  Ok(params)
}
