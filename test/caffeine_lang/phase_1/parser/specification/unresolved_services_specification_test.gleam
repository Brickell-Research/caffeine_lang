import caffeine_lang/phase_1/parser/specification/unresolved_services_specification
import caffeine_lang/phase_1/types.{ServiceUnresolved}

pub fn parse_services_test() {
  let expected_services = [
    ServiceUnresolved(name: "reliable_service", sli_types: [
      "latency",
      "error_rate",
    ]),
    ServiceUnresolved(name: "unreliable_service", sli_types: [
      "error_rate",
    ]),
  ]

  let actual =
    unresolved_services_specification.parse_unresolved_services_specification(
      "test/artifacts/specifications/services.yaml",
    )
  assert actual == Ok(expected_services)
}

pub fn parse_services_missing_sli_types_test() {
  let actual =
    unresolved_services_specification.parse_unresolved_services_specification(
      "test/artifacts/specifications/services_missing_sli_types.yaml",
    )
  assert actual == Error("Missing sli_types")
}

pub fn parse_services_missing_name_test() {
  let actual =
    unresolved_services_specification.parse_unresolved_services_specification(
      "test/artifacts/specifications/services_missing_name.yaml",
    )
  assert actual == Error("Missing name")
}
