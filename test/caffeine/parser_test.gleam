import caffeine/intermediate_representation
import caffeine/parser
import gleam/dict

pub fn parse_instantiation_no_slos_test() {
  let expected_team =
    intermediate_representation.Team(name: "badass_platform_team", slos: [])

  let actual =
    parser.parse_instantiation(
      "test/artifacts/platform/less_reliable_service.yaml",
    )
  assert actual == Ok([expected_team])
}

pub fn parse_instantiation_multiple_slos_test() {
  let expected_slo =
    intermediate_representation.Slo(
      filters: dict.from_list([#("acceptable_status_codes", "[200, 201]")]),
      threshold: 99.5,
      sli_type: "http_status_code",
      service_name: "super_scalabale_web_service",
    )

  let expected_slo_2 =
    intermediate_representation.Slo(
      filters: dict.from_list([#("acceptable_status_codes", "[203, 204]")]),
      threshold: 99.99,
      sli_type: "http_status_code",
      service_name: "super_scalabale_web_service",
    )

  let expected_team =
    intermediate_representation.Team(name: "badass_platform_team", slos: [
      expected_slo,
      expected_slo_2,
    ])

  let actual =
    parser.parse_instantiation("test/artifacts/platform/reliable_service.yaml")
  assert actual == Ok([expected_team])
}
