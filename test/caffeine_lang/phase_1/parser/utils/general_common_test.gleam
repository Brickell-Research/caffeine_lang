import caffeine_lang/types/common/accepted_types
import caffeine_lang/phase_1/parser/utils/general_common
import gleam/dict
import startest.{describe, it}
import startest/expect

pub fn general_common_tests() {
  describe("General Common Utilities", [
    describe("extract_params_from_file_path", [
      it("extracts team and service names from valid file path", fn() {
        let actual =
          general_common.extract_params_from_file_path(
            "test/artifacts/platform/reliable_service.yaml",
          )
        expect.to_equal(
          actual,
          Ok(
            dict.from_list([
              #("team_name", "platform"),
              #("service_name", "reliable_service"),
            ]),
          ),
        )
      }),
      it("returns error for invalid file path", fn() {
        let actual =
          general_common.extract_params_from_file_path("reliable_service.yaml")
        expect.to_equal(
          actual,
          Error("Invalid file path: expected at least 'team/service.yaml'"),
        )
      }),
    ]),
    describe("string_to_accepted_type", [
      it("converts string to Boolean type", fn() {
        let actual = general_common.string_to_accepted_type("Boolean")
        expect.to_equal(actual, Ok(accepted_types.Boolean))
      }),
    ]),
  ])
}
