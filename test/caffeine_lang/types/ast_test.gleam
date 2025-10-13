import caffeine_lang/cql/parser.{ExpContainer, Primary, PrimaryWord, Word}
import caffeine_lang/types/ast/basic_type
import caffeine_lang/types/ast/organization
import caffeine_lang/types/ast/query_template_type
import caffeine_lang/types/ast/service
import caffeine_lang/types/ast/sli_type
import caffeine_lang/types/ast/slo
import caffeine_lang/types/ast/team
import caffeine_lang/types/common/accepted_types
import caffeine_lang/types/common/generic_dictionary
import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

pub fn creates_organization_with_teams_and_services_test() {
  // ==== Specification ====
  let _some_basic_type =
    basic_type.BasicType(
      attribute_name: "acceptable_status_codes",
      attribute_type: accepted_types.List(accepted_types.String),
    )

  let metric_attrs =
    generic_dictionary.from_string_dict(
      dict.from_list([#("numerator_query", ""), #("denominator_query", "")]),
      dict.from_list([
        #("numerator_query", accepted_types.String),
        #("denominator_query", accepted_types.String),
      ]),
    )
    |> result.unwrap(generic_dictionary.new())

  let some_sli_type =
    sli_type.SliType(
      name: "http_status_code",
      query_template_type: query_template_type.QueryTemplateType(
        specification_of_query_templates: [],
        name: "good_over_bad",
        query: ExpContainer(Primary(PrimaryWord(Word("")))),
      ),
      typed_instatiation_of_query_templates: metric_attrs,
      specification_of_query_templatized_variables: [],
    )
  let service_definition =
    service.Service(name: "super_scalabale_web_service", supported_sli_types: [
      some_sli_type,
    ])

  // ==== Instantiation ====
  let filters =
    generic_dictionary.from_string_dict(
      dict.from_list([#("acceptable_status_codes", "[200, 201]")]),
      dict.from_list([
        #(
          "acceptable_status_codes",
          accepted_types.List(accepted_types.Integer),
        ),
      ]),
    )
    |> result.unwrap(generic_dictionary.new())

  let some_slo =
    slo.Slo(
      name: "test_slo",
      typed_instatiation_of_query_templatized_variables: filters,
      threshold: 99.5,
      sli_type: "http_status_code",
      service_name: "super_scalabale_web_service",
      window_in_days: 30,
    )

  let platform_team_definition =
    team.Team(name: "badass_platform_team", slos: [
      some_slo,
    ])

  let some_slo_2 =
    slo.Slo(
      name: "test_slo_2",
      typed_instatiation_of_query_templatized_variables: filters,
      // Reuse the same filters from above
      threshold: 99.5,
      sli_type: "http_status_code",
      service_name: "super_scalabale_web_service",
      window_in_days: 30,
    )

  let other_team_definition = team.Team(name: "other_team", slos: [some_slo_2])

  // ==== Organization ====
  let organization_definition =
    organization.Organization(
      teams: [platform_team_definition, other_team_definition],
      service_definitions: [service_definition],
    )

  let expected_team_names = ["badass_platform_team", "other_team"]
  let actual_team_names =
    organization_definition.teams
    |> list.map(fn(team) { team.name })
    |> list.sort(string.compare)

  actual_team_names
  |> should.equal(expected_team_names)
}
