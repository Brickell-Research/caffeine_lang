import caffeine_lang/common_types/accepted_types
import gleam/dict
import gleam/list
import gleam/result
import gleam/string

// ==== Public ====

/// Converts a string to an accepted type.
pub fn string_to_accepted_type(string: String) -> Result(accepted_types.AcceptedTypes, String) {
  case string {
    "Boolean" -> Ok(accepted_types.Boolean)
    "Decimal" -> Ok(accepted_types.Decimal)
    "Integer" -> Ok(accepted_types.Integer)
    "String" -> Ok(accepted_types.String)
    "List(String)" -> Ok(accepted_types.List(accepted_types.String))
    _ -> Error("Unknown attribute type: " <> string)
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
