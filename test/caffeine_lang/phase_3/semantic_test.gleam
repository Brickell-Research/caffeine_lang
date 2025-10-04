import caffeine_lang/cql/parser.{ExpContainer, Primary, PrimaryWord, Word}
import caffeine_lang/errors/semantic as semantic_errors
import caffeine_lang/phase_3/semantic
import caffeine_lang/types/ast/organization
import caffeine_lang/types/ast/query_template_type
import caffeine_lang/types/ast/service
import caffeine_lang/types/ast/sli_type
import caffeine_lang/types/ast/slo
import caffeine_lang/types/ast/team
import caffeine_lang/types/common/accepted_types
import caffeine_lang/types/common/generic_dictionary
import gleam/dict
import gleam/result
import gleeunit/should

fn team_1() -> team.Team {
  team.Team(name: "team1", slos: [
    slo.Slo(
      typed_instatiation_of_query_templatized_variables: generic_dictionary.new(),
      threshold: 99.9,
      sli_type: "availability",
      service_name: "team1",
      window_in_days: 30,
    ),
    slo.Slo(
      typed_instatiation_of_query_templatized_variables: generic_dictionary.new(),
      threshold: 99.9,
      sli_type: "availability",
      service_name: "team2",
      window_in_days: 30,
    ),
  ])
}

pub fn validate_services_from_instantiation_returns_error_when_services_are_not_defined_test() {
  let organization =
    organization.Organization(service_definitions: [], teams: [team_1()])

  let actual = semantic.validate_services_from_instantiation(organization)
  let expected =
    Error(
      semantic_errors.UndefinedServiceError(service_names: ["team1", "team2"]),
    )

  actual
  |> should.equal(expected)
}

pub fn validate_services_from_instantiation_succeeds_when_all_services_are_defined_test() {
  let organization =
    organization.Organization(
      service_definitions: [
        service.Service(name: "team1", supported_sli_types: []),
        service.Service(name: "team2", supported_sli_types: []),
      ],
      teams: [team_1()],
    )

  let actual = semantic.validate_services_from_instantiation(organization)
  let expected = Ok(True)

  actual
  |> should.equal(expected)
}

pub fn validate_sli_types_exist_from_instantiation_returns_error_when_sli_types_are_not_defined_test() {
  let organization =
    organization.Organization(service_definitions: [], teams: [team_1()])

  let actual =
    semantic.validate_sli_types_exist_from_instantiation(organization)
  let expected =
    Error(
      semantic_errors.UndefinedSliTypeError(sli_type_names: ["availability"]),
    )

  actual
  |> should.equal(expected)
}

pub fn validate_sli_types_exist_from_instantiation_succeeds_when_all_sli_types_are_defined_test() {
  let organization =
    organization.Organization(
      service_definitions: [
        service.Service(name: "team1", supported_sli_types: [
          sli_type.SliType(
            name: "availability",
            query_template_type: query_template_type.QueryTemplateType(
              specification_of_query_templates: [],
              name: "good_over_bad",
              query: ExpContainer(Primary(PrimaryWord(Word("")))),
            ),
            typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
              dict.from_list([
                #("numerator_query", ""),
                #("denominator_query", ""),
              ]),
              dict.from_list([
                #("numerator_query", accepted_types.String),
                #("denominator_query", accepted_types.String),
              ]),
            )
              |> result.unwrap(generic_dictionary.new()),
            specification_of_query_templatized_variables: [],
          ),
        ]),
      ],
      teams: [team_1()],
    )

  let actual =
    semantic.validate_sli_types_exist_from_instantiation(organization)
  let expected = Ok(True)

  actual
  |> should.equal(expected)
}

pub fn validate_slos_thresholds_reasonable_from_instantiation_returns_error_for_invalid_thresholds_test() {
  let organization =
    organization.Organization(service_definitions: [], teams: [
      team.Team(name: "team1", slos: [
        slo.Slo(
          typed_instatiation_of_query_templatized_variables: generic_dictionary.new(),
          threshold: 150.0,
          sli_type: "availability",
          service_name: "team1",
          window_in_days: 30,
        ),
      ]),
    ])

  let actual =
    semantic.validate_slos_thresholds_reasonable_from_instantiation(
      organization,
    )
  let expected =
    Error(
      semantic_errors.InvalidSloThresholdError([150.0]),
    )

  actual
  |> should.equal(expected)
}

pub fn validate_slos_thresholds_reasonable_from_instantiation_succeeds_for_valid_thresholds_test() {
  let organization =
    organization.Organization(service_definitions: [], teams: [team_1()])

  let actual =
    semantic.validate_slos_thresholds_reasonable_from_instantiation(
      organization,
    )
  let expected = Ok(True)

  actual
  |> should.equal(expected)
}

pub fn perform_semantic_analysis_succeeds_when_all_validations_pass_test() {
  let organization =
    organization.Organization(
      teams: [
        team.Team(name: "team1", slos: [
          slo.Slo(
            typed_instatiation_of_query_templatized_variables: generic_dictionary.new(),
            threshold: 99.9,
            sli_type: "availability",
            service_name: "team1",
            window_in_days: 30,
          ),
        ]),
        team.Team(name: "team2", slos: [
          slo.Slo(
            typed_instatiation_of_query_templatized_variables: generic_dictionary.new(),
            threshold: 99.9,
            sli_type: "availability",
            service_name: "team2",
            window_in_days: 30,
          ),
        ]),
      ],
      service_definitions: [
        service.Service(
          name: "team1",
          supported_sli_types: [
            sli_type.SliType(
              name: "availability",
              query_template_type: query_template_type.QueryTemplateType(
                specification_of_query_templates: [],
                name: "good_over_bad",
                query: ExpContainer(Primary(PrimaryWord(Word("")))),
              ),
              typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
                dict.from_list([
                  #("numerator_query", ""),
                  #("denominator_query", ""),
                ]),
                dict.from_list([
                  #("numerator_query", accepted_types.String),
                  #("denominator_query", accepted_types.String),
                ]),
              )
                |> result.unwrap(generic_dictionary.new()),
              specification_of_query_templatized_variables: [],
            ),
          ],
        ),
        service.Service(
          name: "team2",
          supported_sli_types: [
            sli_type.SliType(
              name: "availability",
              query_template_type: query_template_type.QueryTemplateType(
                specification_of_query_templates: [],
                name: "good_over_bad",
                query: ExpContainer(Primary(PrimaryWord(Word("")))),
              ),
              typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
                dict.from_list([
                  #("numerator_query", ""),
                  #("denominator_query", ""),
                ]),
                dict.from_list([
                  #("numerator_query", accepted_types.String),
                  #("denominator_query", accepted_types.String),
                ]),
              )
                |> result.unwrap(generic_dictionary.new()),
              specification_of_query_templatized_variables: [],
            ),
          ],
        ),
      ],
    )

  let actual = semantic.perform_semantic_analysis(organization)
  let expected = Ok(True)

  actual
  |> should.equal(expected)
}

pub fn perform_semantic_analysis_fails_when_any_validation_fails_test() {
  let organization =
    organization.Organization(
      service_definitions: [],
      teams: [team_1()],
    )

  let actual = semantic.perform_semantic_analysis(organization)

  actual
  |> should.be_error()
}
