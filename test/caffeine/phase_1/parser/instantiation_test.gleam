import caffeine/types/intermediate_representation
import caffeine/phase_1/parser/instantiation
import gleam/dict

pub fn parse_instantiation_no_slos_test() {
  let actual =
    instantiation.parse_instantiation(
      "test/artifacts/platform/less_reliable_service.yaml",
    )
  assert actual
    == Error(
      "Empty YAML file: test/artifacts/platform/less_reliable_service.yaml",
    )
}

pub fn parse_instantiation_multiple_slos_test() {
  let expected_slo =
    intermediate_representation.Slo(
      filters: dict.from_list([#("acceptable_status_codes", "[200, 201]")]),
      threshold: 99.5,
      sli_type: "http_status_code",
      service_name: "reliable_service",
    )

  let expected_slo_2 =
    intermediate_representation.Slo(
      filters: dict.from_list([#("acceptable_status_codes", "[203, 204]")]),
      threshold: 99.99,
      sli_type: "http_status_code",
      service_name: "reliable_service",
    )

  let expected_team =
    intermediate_representation.Team(name: "platform", slos: [
      expected_slo,
      expected_slo_2,
    ])

  let actual =
    instantiation.parse_instantiation(
      "test/artifacts/platform/reliable_service.yaml",
    )
  assert actual == Ok(expected_team)
}

pub fn parse_instantiation_missing_sli_type_test() {
  let actual =
    instantiation.parse_instantiation(
      "test/artifacts/platform/reliable_service_missing_sli_type.yaml",
    )
  assert actual == Error("Missing sli_type")
}

pub fn parse_instantiation_missing_filters_test() {
  let actual =
    instantiation.parse_instantiation(
      "test/artifacts/platform/reliable_service_missing_filters.yaml",
    )
  assert actual == Error("Missing filters")
}

pub fn parse_instantiation_missing_threshold_test() {
  let actual =
    instantiation.parse_instantiation(
      "test/artifacts/platform/reliable_service_missing_threshold.yaml",
    )
  assert actual == Error("Missing threshold")
}

pub fn parse_instantiation_missing_slos_test() {
  let actual =
    instantiation.parse_instantiation(
      "test/artifacts/platform/reliable_service_missing_slos.yaml",
    )
  assert actual == Error("Missing SLOs")
}

pub fn parse_instantiation_invalid_threshold_type_test() {
  let actual =
    instantiation.parse_instantiation(
      "test/artifacts/platform/reliable_service_invalid_threshold_type.yaml",
    )
  assert actual == Error("Expected threshold to be a float")
}

pub fn parse_instantiation_invalid_sli_type_type_test() {
  let actual =
    instantiation.parse_instantiation(
      "test/artifacts/platform/reliable_service_invalid_sli_type_type.yaml",
    )
  assert actual == Error("Expected sli_type to be a string")
}
