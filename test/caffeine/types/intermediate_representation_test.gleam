import caffeine/types/intermediate_representation
import gleam/dict
import gleam/list
import gleam/string

pub fn organization_test() {
  // ==== Specfication ====
  let some_sli_filter =
    intermediate_representation.SliFilter(
      attribute_name: "acceptable_status_codes",
      attribute_type: intermediate_representation.List(
        intermediate_representation.String,
      ),
      required: True,
    )

  let some_sli_type =
    intermediate_representation.SliType(
      filters: [some_sli_filter],
      name: "http_status_code",
      query_template: "SELECT count(1) FROM http_requests WHERE status_code IN {acceptable_status_codes}",
    )
  let service_definition =
    intermediate_representation.Service(
      name: "super_scalabale_web_service",
      supported_sli_types: [some_sli_type],
    )

  // ==== Instantiation ====
  let some_slo =
    intermediate_representation.Slo(
      filters: dict.from_list([#("acceptable_status_codes", "[200, 201]")]),
      threshold: 99.5,
      sli_type: "http_status_code",
      service_name: "super_scalabale_web_service",
    )

  let platform_team_definition =
    intermediate_representation.Team(name: "badass_platform_team", slos: [
      some_slo,
    ])

  let some_slo_2 =
    intermediate_representation.Slo(
      filters: dict.from_list([#("acceptable_status_codes", "[200, 201]")]),
      threshold: 99.5,
      sli_type: "http_status_code",
      service_name: "super_scalabale_web_service",
    )

  let other_team_definition =
    intermediate_representation.Team(name: "other_team", slos: [some_slo_2])

  // ==== Organization ====
  let organization_definition =
    intermediate_representation.Organization(
      teams: [platform_team_definition, other_team_definition],
      service_definitions: [service_definition],
    )

  let expected_team_names = ["badass_platform_team", "other_team"]
  let actual_team_names =
    organization_definition.teams
    |> list.map(fn(team) { team.name })
    |> list.sort(string.compare)

  assert actual_team_names == expected_team_names
}
