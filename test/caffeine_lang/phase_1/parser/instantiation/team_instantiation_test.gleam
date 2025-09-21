import caffeine_lang/phase_1/parser/instantiation/team_instantiation
import caffeine_lang/phase_1/types as unresolved_types
import gleam/dict

pub fn parse_instantiation_no_slos_test() {
  let actual =
    team_instantiation.parse_team_instantiation(
      "test/artifacts/platform/less_reliable_service.yaml",
    )
  assert actual
    == Error(
      "Empty YAML file: test/artifacts/platform/less_reliable_service.yaml",
    )
}

pub fn parse_instantiation_multiple_slos_test() {
  let expected_slo =
    unresolved_types.UnresolvedSlo(
      typed_instatiation_of_query_templatized_variables: dict.from_list([
        #("acceptable_status_codes", "[200, 201]"),
      ]),
      threshold: 99.5,
      sli_type: "http_status_code",
      service_name: "reliable_service",
      window_in_days: 30,
    )

  let expected_slo_2 =
    unresolved_types.UnresolvedSlo(
      typed_instatiation_of_query_templatized_variables: dict.from_list([
        #("acceptable_status_codes", "[203, 204]"),
      ]),
      threshold: 99.99,
      sli_type: "http_status_code",
      service_name: "reliable_service",
      window_in_days: 30,
    )

  let expected_team =
    unresolved_types.UnresolvedTeam(name: "platform", slos: [
      expected_slo,
      expected_slo_2,
    ])

  let actual =
    team_instantiation.parse_team_instantiation(
      "test/artifacts/platform/reliable_service.yaml",
    )
  assert actual == Ok(expected_team)
}

pub fn parse_instantiation_missing_sli_type_test() {
  let actual =
    team_instantiation.parse_team_instantiation(
      "test/artifacts/platform/reliable_service_missing_sli_type.yaml",
    )
  assert actual == Error("Missing sli_type")
}

pub fn parse_instantiation_missing_filters_test() {
  let actual =
    team_instantiation.parse_team_instantiation(
      "test/artifacts/platform/reliable_service_missing_typed_instatiation_of_query_templatized_variables.yaml",
    )
  assert actual
    == Error("Missing typed_instatiation_of_query_templatized_variables")
}

pub fn parse_instantiation_missing_threshold_test() {
  let actual =
    team_instantiation.parse_team_instantiation(
      "test/artifacts/platform/reliable_service_missing_threshold.yaml",
    )
  assert actual == Error("Missing threshold")
}

pub fn parse_instantiation_missing_slos_test() {
  let actual =
    team_instantiation.parse_team_instantiation(
      "test/artifacts/platform/reliable_service_missing_slos.yaml",
    )
  assert actual == Error("Missing slos")
}

pub fn parse_instantiation_invalid_threshold_type_test() {
  let actual =
    team_instantiation.parse_team_instantiation(
      "test/artifacts/platform/reliable_service_invalid_threshold_type.yaml",
    )
  assert actual == Error("Expected threshold to be a float")
}

pub fn parse_instantiation_invalid_sli_type_type_test() {
  let actual =
    team_instantiation.parse_team_instantiation(
      "test/artifacts/platform/reliable_service_invalid_sli_type_type.yaml",
    )
  assert actual == Error("Expected sli_type to be a string")
}
