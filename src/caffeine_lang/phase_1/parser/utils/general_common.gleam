import caffeine_lang/types/accepted_types.{
  type AcceptedTypes, Boolean, Decimal, Integer, List, String,
}
import gleam/dict
import gleam/list
import gleam/result
import gleam/string

// ==== Public ====

/// Converts a string to an accepted type.
pub fn string_to_accepted_type(string: String) -> Result(AcceptedTypes, String) {
  case string {
    "Boolean" -> Ok(Boolean)
    "Decimal" -> Ok(Decimal)
    "Integer" -> Ok(Integer)
    "String" -> Ok(String)
    "List(String)" -> Ok(List(String))
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
