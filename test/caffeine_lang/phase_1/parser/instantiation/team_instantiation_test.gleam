import caffeine_lang/phase_1/parser/common_parse_test_utils
import caffeine_lang/phase_1/parser/instantiation/team_instantiation
import caffeine_lang/types/unresolved/unresolved_slo
import caffeine_lang/types/unresolved/unresolved_team
import gleam/dict
import startest.{describe, it}
import startest/expect

fn assert_parse_error(file_path: String, expected: String) {
  common_parse_test_utils.assert_parse_error(
    team_instantiation.parse_team_instantiation,
    file_path,
    expected,
  )
}

pub fn team_instantiation_tests() {
  describe("Team Instantiation Parser", [
    describe("parse_team_instantiation", [
      it("returns error for empty YAML file", fn() {
        assert_parse_error(
          "test/artifacts/platform/less_reliable_service.yaml",
          "Empty YAML file: test/artifacts/platform/less_reliable_service.yaml",
        )
      }),
      it("parses multiple SLOs successfully", fn() {
        let expected_slo =
          unresolved_slo.Slo(
            typed_instatiation_of_query_templatized_variables: dict.from_list([
              #("acceptable_status_codes", "[200, 201]"),
            ]),
            threshold: 99.5,
            sli_type: "http_status_code",
            service_name: "reliable_service",
            window_in_days: 30,
          )

        let expected_slo_2 =
          unresolved_slo.Slo(
            typed_instatiation_of_query_templatized_variables: dict.from_list([
              #("acceptable_status_codes", "[203, 204]"),
            ]),
            threshold: 99.99,
            sli_type: "http_status_code",
            service_name: "reliable_service",
            window_in_days: 30,
          )

        let expected_team =
          unresolved_team.Team(name: "platform", slos: [
            expected_slo,
            expected_slo_2,
          ])

        let actual =
          team_instantiation.parse_team_instantiation(
            "test/artifacts/platform/reliable_service.yaml",
          )
        expect.to_equal(actual, Ok(expected_team))
      }),
      it("returns error when sli_type is missing", fn() {
        assert_parse_error(
          "test/artifacts/platform/reliable_service_missing_sli_type.yaml",
          "Missing sli_type",
        )
      }),
      it("returns error when filters are missing", fn() {
        assert_parse_error(
          "test/artifacts/platform/reliable_service_missing_typed_instatiation_of_query_templatized_variables.yaml",
          "Missing typed_instatiation_of_query_templatized_variables",
        )
      }),
      it("returns error when threshold is missing", fn() {
        assert_parse_error(
          "test/artifacts/platform/reliable_service_missing_threshold.yaml",
          "Missing threshold",
        )
      }),
      it("returns error when slos are missing", fn() {
        assert_parse_error(
          "test/artifacts/platform/reliable_service_missing_slos.yaml",
          "Missing slos",
        )
      }),
      it("returns error for invalid threshold type", fn() {
        assert_parse_error(
          "test/artifacts/platform/reliable_service_invalid_threshold_type.yaml",
          "Expected threshold to be a float",
        )
      }),
      it("returns error for invalid sli_type type", fn() {
        assert_parse_error(
          "test/artifacts/platform/reliable_service_invalid_sli_type_type.yaml",
          "Expected sli_type to be a string",
        )
      }),
    ]),
  ])
}
