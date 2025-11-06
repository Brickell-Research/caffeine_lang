import caffeine_lang/phase_1/parser/specification/unresolved_services_specification
import caffeine_lang/types/unresolved/unresolved_service
import gleam/result
import gleamy_spec/extensions.{describe, it}
import gleamy_spec/gleeunit

pub fn parse_unresolved_services_specification_test() {
  describe("parse_unresolved_services_specification", fn() {
    it("should parse valid services", fn() {
      let expected_services = [
        unresolved_service.Service(name: "reliable_service", sli_types: [
          "latency",
          "error_rate",
        ]),
        unresolved_service.Service(name: "unreliable_service", sli_types: [
          "error_rate",
        ]),
      ]

      let actual =
        unresolved_services_specification.parse_unresolved_services_specification(
          "test/caffeine_lang/artifacts/specifications/services.yaml",
        )

      actual
      |> gleeunit.equal(Ok(expected_services))
    })

    it("should return an error when sli_types is missing", fn() {
      let actual =
        unresolved_services_specification.parse_unresolved_services_specification(
          "test/caffeine_lang/artifacts/specifications/services_missing_sli_types.yaml",
        )

      actual
      |> result.is_error()
      |> gleeunit.be_true()

      case actual {
        Error(msg) ->
          msg
          |> gleeunit.equal("Missing sli_types")
        Ok(_) -> panic as "Expected error"
      }
    })

    it("should return an error when name is missing", fn() {
      let actual =
        unresolved_services_specification.parse_unresolved_services_specification(
          "test/caffeine_lang/artifacts/specifications/services_missing_name.yaml",
        )

      actual
      |> result.is_error()
      |> gleeunit.be_true()

      case actual {
        Error(msg) ->
          msg
          |> gleeunit.equal("Missing name")
        Ok(_) -> panic as "Expected error"
      }
    })
  })
}
