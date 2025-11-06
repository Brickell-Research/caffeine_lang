import caffeine_lang/phase_1/parser/specification/unresolved_services_specification
import caffeine_lang/types/unresolved/unresolved_service
import deps/gleamy_spec/extensions.{describe, it}
import deps/gleamy_spec/gleeunit

pub fn parse_unresolved_services_specification_test() {
  describe("parse_unresolved_services_specification", fn() {
    describe("valid services", fn() {
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

        unresolved_services_specification.parse_unresolved_services_specification(
          "test/caffeine_lang/artifacts/specifications/services.yaml",
        )
        |> gleeunit.equal(Ok(expected_services))
      })
    })

    describe("error cases", fn() {
      it("should return an error when sli_types is missing", fn() {
        unresolved_services_specification.parse_unresolved_services_specification(
          "test/caffeine_lang/artifacts/specifications/services_missing_sli_types.yaml",
        )
        |> gleeunit.equal(Error("Missing sli_types"))
      })

      it("should return an error when name is missing", fn() {
        unresolved_services_specification.parse_unresolved_services_specification(
          "test/caffeine_lang/artifacts/specifications/services_missing_name.yaml",
        )
        |> gleeunit.equal(Error("Missing name"))
      })
    })
  })
}
