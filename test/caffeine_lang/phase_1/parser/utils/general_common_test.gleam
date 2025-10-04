import caffeine_lang/phase_1/parser/utils/general_common
import caffeine_lang/types/common/accepted_types
import gleam/dict
import gleeunit/should

pub fn extract_params_from_file_path_extracts_team_and_service_names_from_valid_file_path_test() {
  let actual =
    general_common.extract_params_from_file_path(
      "test/artifacts/platform/reliable_service.yaml",
    )
  
  actual
  |> should.equal(
    Ok(
      dict.from_list([
        #("team_name", "platform"),
        #("service_name", "reliable_service"),
      ]),
    ),
  )
}

pub fn extract_params_from_file_path_returns_error_for_invalid_file_path_test() {
  let actual =
    general_common.extract_params_from_file_path("reliable_service.yaml")
  
  actual
  |> should.equal(
    Error("Invalid file path: expected at least 'team/service.yaml'"),
  )
}

pub fn string_to_accepted_type_converts_string_to_boolean_type_test() {
  let actual = general_common.string_to_accepted_type("Boolean")
  
  actual
  |> should.equal(Ok(accepted_types.Boolean))
}
