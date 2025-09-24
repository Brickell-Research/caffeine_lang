import caffeine_lang/phase_1/parser/specification/unresolved_services_specification
import caffeine_lang/types/unresolved/unresolved_service
import startest.{describe, it}
import startest/expect

pub fn unresolved_services_specification_tests() {
  describe("Unresolved Services Specification Parser", [
    describe("parse_unresolved_services_specification", [
      it("parses valid services", fn() {
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
            "test/artifacts/specifications/services.yaml",
          )
        expect.to_equal(actual, Ok(expected_services))
      }),
      it("returns error when sli_types is missing", fn() {
        let actual =
          unresolved_services_specification.parse_unresolved_services_specification(
            "test/artifacts/specifications/services_missing_sli_types.yaml",
          )
        expect.to_equal(actual, Error("Missing sli_types"))
      }),
      it("returns error when name is missing", fn() {
        let actual =
          unresolved_services_specification.parse_unresolved_services_specification(
            "test/artifacts/specifications/services_missing_name.yaml",
          )
        expect.to_equal(actual, Error("Missing name"))
      }),
    ]),
  ])
}
