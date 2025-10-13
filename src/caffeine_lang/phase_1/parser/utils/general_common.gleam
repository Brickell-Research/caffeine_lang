import caffeine_lang/types/common/accepted_types
import gleam/dict
import gleam/list
import gleam/result
import gleam/string

// ==== Public ====

/// Converts a string to an accepted type.
pub fn string_to_accepted_type(
  string_val: String,
) -> Result(accepted_types.AcceptedTypes, String) {
  let accepted_types = [
    "String",
    "Integer",
    "Boolean",
    "Decimal",
    "List(String)",
    "List(Integer)",
    "List(Boolean)",
    "List(Decimal)",
    "Optional(String)",
    "Optional(Integer)",
    "Optional(Boolean)",
    "Optional(Decimal)",
    "Optional(List(String))",
    "Optional(List(Integer))",
    "Optional(List(Boolean))",
    "Optional(List(Decimal))",
  ]
  case string_val {
    "String" -> Ok(accepted_types.String)
    "Integer" -> Ok(accepted_types.Integer)
    "Boolean" -> Ok(accepted_types.Boolean)
    "Decimal" -> Ok(accepted_types.Decimal)
    "List(String)" -> Ok(accepted_types.List(accepted_types.String))
    "List(Integer)" -> Ok(accepted_types.List(accepted_types.Integer))
    "List(Boolean)" -> Ok(accepted_types.List(accepted_types.Boolean))
    "List(Decimal)" -> Ok(accepted_types.List(accepted_types.Decimal))
    "Optional(String)" -> Ok(accepted_types.Optional(accepted_types.String))
    "Optional(Integer)" -> Ok(accepted_types.Optional(accepted_types.Integer))
    "Optional(Boolean)" -> Ok(accepted_types.Optional(accepted_types.Boolean))
    "Optional(Decimal)" -> Ok(accepted_types.Optional(accepted_types.Decimal))
    "Optional(List(String))" ->
      Ok(accepted_types.Optional(accepted_types.List(accepted_types.String)))
    "Optional(List(Integer))" ->
      Ok(accepted_types.Optional(accepted_types.List(accepted_types.Integer)))
    "Optional(List(Boolean))" ->
      Ok(accepted_types.Optional(accepted_types.List(accepted_types.Boolean)))
    "Optional(List(Decimal))" ->
      Ok(accepted_types.Optional(accepted_types.List(accepted_types.Decimal)))
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
                <> ". Supported: "
                <> string.join(accepted_types, ", "),
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
