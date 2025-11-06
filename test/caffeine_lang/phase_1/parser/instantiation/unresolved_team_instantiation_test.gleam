import caffeine_lang/phase_1/parser/instantiation/unresolved_team_instantiation
import caffeine_lang/types/unresolved/unresolved_slo
import caffeine_lang/types/unresolved/unresolved_team
import deps/gleamy_spec/extensions.{describe, it}
import deps/gleamy_spec/gleeunit
import gleam/dict
import gleam/result

pub fn parse_unresolved_team_instantiation_test() {
  describe("parse_unresolved_team_instantiation", fn() {
    describe("valid team instantiation", fn() {
      it("should return an error for empty yaml file", fn() {
        unresolved_team_instantiation.parse_unresolved_team_instantiation(
          "test/caffeine_lang/artifacts/platform/less_reliable_service.yaml",
        )
        |> gleeunit.equal(Error(
          "Empty YAML file: test/caffeine_lang/artifacts/platform/less_reliable_service.yaml",
        ))
      })

      it("should parse multiple slos successfully", fn() {
        let expected_slo =
          unresolved_slo.Slo(
            name: "success_codes",
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
            name: "alternate_success_codes",
            typed_instatiation_of_query_templatized_variables: dict.from_list([
              #("acceptable_status_codes", "[203, 204]"),
            ]),
            threshold: 99.99,
            sli_type: "http_status_code",
            service_name: "reliable_service",
            window_in_days: 30,
          )

        unresolved_team_instantiation.parse_unresolved_team_instantiation(
          "test/caffeine_lang/artifacts/platform/reliable_service.yaml",
        )
        |> gleeunit.equal(
          Ok(
            unresolved_team.Team(name: "platform", slos: [
              expected_slo,
              expected_slo_2,
            ]),
          ),
        )
      })
    })

    describe("error cases", fn() {
      it("should return an error when sli_type is missing", fn() {
        unresolved_team_instantiation.parse_unresolved_team_instantiation(
          "test/caffeine_lang/artifacts/platform/reliable_service_missing_sli_type.yaml",
        )
        |> gleeunit.equal(Error("Missing sli_type"))
      })

      it("should return ok when filters are missing", fn() {
        // Should succeed with empty dict when typed_instatiation_of_query_templatized_variables is missing
        unresolved_team_instantiation.parse_unresolved_team_instantiation(
          "test/caffeine_lang/artifacts/platform/reliable_service_missing_typed_instatiation_of_query_templatized_variables.yaml",
        )
        |> result.is_ok()
        |> gleeunit.be_true()
      })

      it("should return an error when threshold is missing", fn() {
        unresolved_team_instantiation.parse_unresolved_team_instantiation(
          "test/caffeine_lang/artifacts/platform/reliable_service_missing_threshold.yaml",
        )
        |> gleeunit.equal(Error("Missing threshold"))
      })

      it("should return an error when slos are missing", fn() {
        unresolved_team_instantiation.parse_unresolved_team_instantiation(
          "test/caffeine_lang/artifacts/platform/reliable_service_missing_slos.yaml",
        )
        |> gleeunit.equal(Error("Missing slos"))
      })

      it("should return an error for invalid threshold type", fn() {
        unresolved_team_instantiation.parse_unresolved_team_instantiation(
          "test/caffeine_lang/artifacts/platform/reliable_service_invalid_threshold_type.yaml",
        )
        |> gleeunit.equal(Error("Expected threshold to be a float"))
      })

      it("should return an error for invalid sli_type type", fn() {
        unresolved_team_instantiation.parse_unresolved_team_instantiation(
          "test/caffeine_lang/artifacts/platform/reliable_service_invalid_sli_type_type.yaml",
        )
        |> gleeunit.equal(Error("Expected sli_type to be a string"))
      })

      it("should return an error when name is missing", fn() {
        unresolved_team_instantiation.parse_unresolved_team_instantiation(
          "test/caffeine_lang/artifacts/platform/reliable_service_missing_name.yaml",
        )
        |> gleeunit.equal(Error("Missing name"))
      })
    })
  })
}
