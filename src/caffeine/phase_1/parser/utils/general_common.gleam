import caffeine/types/intermediate_representation
import gleam/list
import gleam/string

// ==== Public ====
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

/// Converts a string to an accepted type.
pub fn string_to_accepted_type(
  string: String,
) -> Result(intermediate_representation.AcceptedTypes, String) {
  case string {
    "Boolean" -> Ok(intermediate_representation.Boolean)
    "Decimal" -> Ok(intermediate_representation.Decimal)
    "Integer" -> Ok(intermediate_representation.Integer)
    "String" -> Ok(intermediate_representation.String)
    "List(String)" ->
      Ok(intermediate_representation.List(intermediate_representation.String))
    _ -> Error("Unknown attribute type: " <> string)
  }
}
