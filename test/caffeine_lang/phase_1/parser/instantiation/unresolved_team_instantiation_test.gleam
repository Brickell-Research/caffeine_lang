import caffeine_lang/phase_1/parser/instantiation/unresolved_team_instantiation
import caffeine_lang/types/unresolved/unresolved_slo
import caffeine_lang/types/unresolved/unresolved_team
import gleam/dict
import gleam/result
import gleamy_spec/extensions.{describe, it}
import gleamy_spec/gleeunit

pub fn parse_unresolved_team_instantiation_test() {
  describe("parse_unresolved_team_instantiation", fn() {
    it("should return an error for empty yaml file", fn() {
      let actual =
        unresolved_team_instantiation.parse_unresolved_team_instantiation(
          "test/caffeine_lang/artifacts/platform/less_reliable_service.yaml",
        )

      actual
      |> result.is_error()
      |> gleeunit.be_true()

      case actual {
        Error(msg) ->
          msg
          |> gleeunit.equal(
            "Empty YAML file: test/caffeine_lang/artifacts/platform/less_reliable_service.yaml",
          )
        Ok(_) -> panic as "Expected error"
      }
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

      let expected_team =
        unresolved_team.Team(name: "platform", slos: [
          expected_slo,
          expected_slo_2,
        ])

      let actual =
        unresolved_team_instantiation.parse_unresolved_team_instantiation(
          "test/caffeine_lang/artifacts/platform/reliable_service.yaml",
        )

      actual
      |> gleeunit.equal(Ok(expected_team))
    })

    describe("error cases", fn() {
      it("should return an error when sli_type is missing", fn() {
        let actual =
          unresolved_team_instantiation.parse_unresolved_team_instantiation(
            "test/caffeine_lang/artifacts/platform/reliable_service_missing_sli_type.yaml",
          )

        case actual {
          Error(msg) ->
            msg
            |> gleeunit.equal("Missing sli_type")
          Ok(_) -> panic as "Expected error"
        }
      })

      it("should return ok when filters are missing", fn() {
        let actual =
          unresolved_team_instantiation.parse_unresolved_team_instantiation(
            "test/caffeine_lang/artifacts/platform/reliable_service_missing_typed_instatiation_of_query_templatized_variables.yaml",
          )

        // Should succeed with empty dict when typed_instatiation_of_query_templatized_variables is missing
        actual
        |> result.is_ok()
        |> gleeunit.be_true()
      })

      it("should return an error when threshold is missing", fn() {
        let actual =
          unresolved_team_instantiation.parse_unresolved_team_instantiation(
            "test/caffeine_lang/artifacts/platform/reliable_service_missing_threshold.yaml",
          )

        case actual {
          Error(msg) ->
            msg
            |> gleeunit.equal("Missing threshold")
          Ok(_) -> panic as "Expected error"
        }
      })

      it("should return an error when slos are missing", fn() {
        let actual =
          unresolved_team_instantiation.parse_unresolved_team_instantiation(
            "test/caffeine_lang/artifacts/platform/reliable_service_missing_slos.yaml",
          )

        case actual {
          Error(msg) ->
            msg
            |> gleeunit.equal("Missing slos")
          Ok(_) -> panic as "Expected error"
        }
      })

      it("should return an error for invalid threshold type", fn() {
        let actual =
          unresolved_team_instantiation.parse_unresolved_team_instantiation(
            "test/caffeine_lang/artifacts/platform/reliable_service_invalid_threshold_type.yaml",
          )

        case actual {
          Error(msg) ->
            msg
            |> gleeunit.equal("Expected threshold to be a float")
          Ok(_) -> panic as "Expected error"
        }
      })

      it("should return an error for invalid sli_type type", fn() {
        let actual =
          unresolved_team_instantiation.parse_unresolved_team_instantiation(
            "test/caffeine_lang/artifacts/platform/reliable_service_invalid_sli_type_type.yaml",
          )

        case actual {
          Error(msg) ->
            msg
            |> gleeunit.equal("Expected sli_type to be a string")
          Ok(_) -> panic as "Expected error"
        }
      })

      it("should return an error when name is missing", fn() {
        let actual =
          unresolved_team_instantiation.parse_unresolved_team_instantiation(
            "test/caffeine_lang/artifacts/platform/reliable_service_missing_name.yaml",
          )

        case actual {
          Error(msg) ->
            msg
            |> gleeunit.equal("Missing name")
          Ok(_) -> panic as "Expected error"
        }
      })
    })
  })
}
