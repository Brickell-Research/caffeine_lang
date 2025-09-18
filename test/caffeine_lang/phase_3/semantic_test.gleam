import caffeine_lang/phase_3/semantic.{
  InvalidSloThresholdError, UndefinedServiceError, UndefinedSliTypeError,
}
import caffeine_lang/types/accepted_types
import caffeine_lang/types/ast.{
  type Team, Organization, QueryTemplateType, Service, SliType, Slo, Team,
}
import caffeine_lang/types/generic_dictionary
import gleam/dict
import gleam/result

fn team_1() -> Team {
  Team(name: "team1", slos: [
    Slo(
      typed_instatiation_of_query_templatized_variables: generic_dictionary.new(),
      threshold: 99.9,
      sli_type: "availability",
      service_name: "team1",
      window_in_days: 30,
    ),
    Slo(
      typed_instatiation_of_query_templatized_variables: generic_dictionary.new(),
      threshold: 99.9,
      sli_type: "availability",
      service_name: "team2",
      window_in_days: 30,
    ),
  ])
}

pub fn validate_services_from_instantiation_failure_test() {
  let organization = Organization(service_definitions: [], teams: [team_1()])

  let actual = semantic.validate_services_from_instantiation(organization)
  let expected = Error(UndefinedServiceError(service_names: ["team1", "team2"]))

  assert actual == expected
}

pub fn validate_services_from_instantiation_success_test() {
  let organization =
    Organization(
      service_definitions: [
        Service(name: "team1", supported_sli_types: []),
        Service(name: "team2", supported_sli_types: []),
      ],
      teams: [team_1()],
    )

  let actual = semantic.validate_services_from_instantiation(organization)
  let expected = Ok(True)

  assert actual == expected
}

pub fn validate_sli_types_exist_from_instantiation_failure_test() {
  let organization = Organization(service_definitions: [], teams: [team_1()])

  let actual =
    semantic.validate_sli_types_exist_from_instantiation(organization)
  let expected = Error(UndefinedSliTypeError(sli_type_names: ["availability"]))

  assert actual == expected
}

pub fn validate_sli_types_exist_from_instantiation_success_test() {
  let organization =
    Organization(
      service_definitions: [
        Service(name: "team1", supported_sli_types: [
          SliType(
            name: "availability",
            query_template_type: QueryTemplateType(
              specification_of_query_templates: [],
              name: "good_over_bad",
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
          SliType(
            name: "latency",
            query_template_type: QueryTemplateType(
              specification_of_query_templates: [],
              name: "good_over_bad",
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

  assert actual == expected
}

pub fn validate_slos_thresholds_reasonable_from_instantiation_failure_test() {
  let organization =
    Organization(service_definitions: [], teams: [
      Team(name: "team1", slos: [
        Slo(
          typed_instatiation_of_query_templatized_variables: generic_dictionary.new(),
          threshold: 101.0,
          sli_type: "availability",
          service_name: "team1",
          window_in_days: 30,
        ),
        Slo(
          typed_instatiation_of_query_templatized_variables: generic_dictionary.new(),
          threshold: -1.0,
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
  let expected = Error(InvalidSloThresholdError(thresholds: [101.0, -1.0]))

  assert actual == expected
}

pub fn validate_slos_thresholds_reasonable_from_instantiation_success_test() {
  let organization = Organization(service_definitions: [], teams: [team_1()])

  let actual =
    semantic.validate_slos_thresholds_reasonable_from_instantiation(
      organization,
    )
  let expected = Ok(True)

  assert actual == expected
}

pub fn perform_semantic_analysis_test() {
  let organization =
    Organization(
      service_definitions: [
        Service(name: "team1", supported_sli_types: [
          SliType(
            name: "availability",
            query_template_type: QueryTemplateType(
              specification_of_query_templates: [],
              name: "good_over_bad",
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
          SliType(
            name: "latency",
            query_template_type: QueryTemplateType(
              specification_of_query_templates: [],
              name: "good_over_bad",
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
        Service(name: "team2", supported_sli_types: [
          SliType(
            name: "availability",
            query_template_type: QueryTemplateType(
              specification_of_query_templates: [],
              name: "good_over_bad",
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
          SliType(
            name: "latency",
            query_template_type: QueryTemplateType(
              specification_of_query_templates: [],
              name: "good_over_bad",
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

  let actual = semantic.perform_semantic_analysis(organization)
  let expected = Ok(True)

  assert actual == expected
}

pub fn perform_semantic_analysis_failure_test() {
  let organization = Organization(service_definitions: [], teams: [team_1()])

  let actual = semantic.perform_semantic_analysis(organization)
  let expected = Error(UndefinedServiceError(service_names: ["team1", "team2"]))

  assert actual == expected
}
