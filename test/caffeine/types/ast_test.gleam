import caffeine/types/ast
import gleam/dict
import gleam/list
import gleam/string

pub fn organization_test() {
  // ==== Specfication ====
  let some_query_template_filter =
    ast.QueryTemplateFilter(
      attribute_name: "acceptable_status_codes",
      attribute_type: ast.List(
        ast.String,
      ),
    )

  let some_sli_type =
    ast.SliType(
      name: "http_status_code",
      query_template_type: ast.QueryTemplateType(
        metric_attributes: [some_query_template_filter],
        name: "good_over_bad",
      ),
      metric_attributes: ["numerator_query", "denominator_query"],
      filters: [some_query_template_filter],
    )
  let service_definition =
    ast.Service(
      name: "super_scalabale_web_service",
      supported_sli_types: [some_sli_type],
    )

  // ==== Instantiation ====
  let some_slo =
    ast.Slo(
      filters: dict.from_list([#("acceptable_status_codes", "[200, 201]")]),
      threshold: 99.5,
      sli_type: "http_status_code",
      service_name: "super_scalabale_web_service",
      window_in_days: 30,
    )

  let platform_team_definition =
    ast.Team(name: "badass_platform_team", slos: [
      some_slo,
    ])

  let some_slo_2 =
    ast.Slo(
      filters: dict.from_list([#("acceptable_status_codes", "[200, 201]")]),
      threshold: 99.5,
      sli_type: "http_status_code",
      service_name: "super_scalabale_web_service",
      window_in_days: 30,
    )

  let other_team_definition =
    ast.Team(name: "other_team", slos: [some_slo_2])

  // ==== Organization ====
  let organization_definition =
    ast.Organization(
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
