import caffeine_lang/phase_1/parser/instantiation/unresolved_team_instantiation
import caffeine_lang/types/unresolved/unresolved_slo
import caffeine_lang/types/unresolved/unresolved_team
import gleam/dict
import gleam/result
import gleamy_spec/should

pub fn parse_unresolved_team_instantiation_returns_error_for_empty_yaml_file_test() {
  let actual =
    unresolved_team_instantiation.parse_unresolved_team_instantiation(
      "test/caffeine_lang/artifacts/platform/less_reliable_service.yaml",
    )

  actual
  |> result.is_error()
  |> should.be_true()

  case actual {
    Error(msg) ->
      msg
      |> should.equal(
        "Empty YAML file: test/caffeine_lang/artifacts/platform/less_reliable_service.yaml",
      )
    Ok(_) -> panic as "Expected error"
  }
}

pub fn parse_unresolved_team_instantiation_parses_multiple_slos_successfully_test() {
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
  |> should.equal(Ok(expected_team))
}

pub fn parse_unresolved_team_instantiation_returns_error_when_sli_type_is_missing_test() {
  let actual =
    unresolved_team_instantiation.parse_unresolved_team_instantiation(
      "test/caffeine_lang/artifacts/platform/reliable_service_missing_sli_type.yaml",
    )

  case actual {
    Error(msg) ->
      msg
      |> should.equal("Missing sli_type")
    Ok(_) -> panic as "Expected error"
  }
}

pub fn parse_unresolved_team_instantiation_returns_ok_when_filters_are_missing_test() {
  let actual =
    unresolved_team_instantiation.parse_unresolved_team_instantiation(
      "test/caffeine_lang/artifacts/platform/reliable_service_missing_typed_instatiation_of_query_templatized_variables.yaml",
    )

  // Should succeed with empty dict when typed_instatiation_of_query_templatized_variables is missing
  actual
  |> result.is_ok()
  |> should.be_true()
}

pub fn parse_unresolved_team_instantiation_returns_error_when_threshold_is_missing_test() {
  let actual =
    unresolved_team_instantiation.parse_unresolved_team_instantiation(
      "test/caffeine_lang/artifacts/platform/reliable_service_missing_threshold.yaml",
    )

  case actual {
    Error(msg) ->
      msg
      |> should.equal("Missing threshold")
    Ok(_) -> panic as "Expected error"
  }
}

pub fn parse_unresolved_team_instantiation_returns_error_when_slos_are_missing_test() {
  let actual =
    unresolved_team_instantiation.parse_unresolved_team_instantiation(
      "test/caffeine_lang/artifacts/platform/reliable_service_missing_slos.yaml",
    )

  case actual {
    Error(msg) ->
      msg
      |> should.equal("Missing slos")
    Ok(_) -> panic as "Expected error"
  }
}

pub fn parse_unresolved_team_instantiation_returns_error_for_invalid_threshold_type_test() {
  let actual =
    unresolved_team_instantiation.parse_unresolved_team_instantiation(
      "test/caffeine_lang/artifacts/platform/reliable_service_invalid_threshold_type.yaml",
    )

  case actual {
    Error(msg) ->
      msg
      |> should.equal("Expected threshold to be a float")
    Ok(_) -> panic as "Expected error"
  }
}

pub fn parse_unresolved_team_instantiation_returns_error_for_invalid_sli_type_type_test() {
  let actual =
    unresolved_team_instantiation.parse_unresolved_team_instantiation(
      "test/caffeine_lang/artifacts/platform/reliable_service_invalid_sli_type_type.yaml",
    )

  case actual {
    Error(msg) ->
      msg
      |> should.equal("Expected sli_type to be a string")
    Ok(_) -> panic as "Expected error"
  }
}

pub fn parse_unresolved_team_instantiation_returns_error_when_name_is_missing_test() {
  let actual =
    unresolved_team_instantiation.parse_unresolved_team_instantiation(
      "test/caffeine_lang/artifacts/platform/reliable_service_missing_name.yaml",
    )

  case actual {
    Error(msg) ->
      msg
      |> should.equal("Missing name")
    Ok(_) -> panic as "Expected error"
  }
}
