import caffeine_lang/types/common/accepted_types
import caffeine_lang/phase_1/parser/utils/general_common
import gleam/dict

pub fn extract_params_from_file_path_test() {
  let actual =
    general_common.extract_params_from_file_path(
      "test/artifacts/platform/reliable_service.yaml",
    )
  assert actual
    == Ok(
      dict.from_list([
        #("team_name", "platform"),
        #("service_name", "reliable_service"),
      ]),
    )
}

pub fn extract_params_from_file_path_invalid_test() {
  let actual =
    general_common.extract_params_from_file_path("reliable_service.yaml")
  assert actual
    == Error("Invalid file path: expected at least 'team/service.yaml'")
}

pub fn string_to_accepted_type_test() {
  let actual = general_common.string_to_accepted_type("Boolean")
  assert actual == Ok(accepted_types.Boolean)
}
