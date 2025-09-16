import caffeine_lang/phase_2/linker/instantiation/linker
import caffeine_lang/types/accepted_types
import caffeine_lang/types/ast.{
  BasicType, QueryTemplateType, Service, SliType, Slo, Team,
}
import caffeine_lang/types/generic_dictionary
import caffeine_lang/types/instantiation_types.{UnresolvedSlo, UnresolvedTeam}
import gleam/dict
import gleam/list
import gleam/string

pub fn aggregate_teams_and_slos_test() {
  let slo_a =
    Slo(
      typed_instatiation_of_query_templatized_variables: create_test_dictionary(),
      threshold: 0.9,
      sli_type: "sli_type_a",
      service_name: "service_a",
      window_in_days: 30,
    )

  let slo_b =
    Slo(
      typed_instatiation_of_query_templatized_variables: create_test_dictionary(),
      threshold: 0.8,
      sli_type: "sli_type_b",
      service_name: "service_b",
      window_in_days: 30,
    )

  let slo_c =
    Slo(
      typed_instatiation_of_query_templatized_variables: create_test_dictionary(),
      threshold: 0.7,
      sli_type: "sli_type_c",
      service_name: "service_c",
      window_in_days: 30,
    )

  let team_a_service_a = Team(name: "team_a", slos: [slo_a])
  let team_a_service_b = Team(name: "team_a", slos: [slo_b])
  let team_b_service_c = Team(name: "team_b", slos: [slo_c])

  let teams = [team_a_service_a, team_a_service_b, team_b_service_c]

  let actual = linker.aggregate_teams_and_slos(teams)

  let expected = [
    Team(name: "team_a", slos: [slo_b, slo_a]),
    Team(name: "team_b", slos: [slo_c]),
  ]

  assert list.sort(actual, fn(a, b) { string.compare(a.name, b.name) })
    == list.sort(expected, fn(a, b) { string.compare(a.name, b.name) })
}

fn create_test_dictionary() -> generic_dictionary.GenericDictionary {
  let values = dict.from_list([#("key", "value")])
  let type_defs = dict.from_list([#("key", accepted_types.String)])
  case generic_dictionary.from_string_dict(values, type_defs) {
    Ok(d) -> d
    Error(_) -> generic_dictionary.new()
  }
}

pub fn resolve_filters_test() {
  let instantiated_filters =
    dict.from_list([
      #("string_key", "string_value"),
      #("int_key", "1"),
      #("decimal_key", "1.1"),
      #("boolean_key", "true"),
      #("list_string_key", "[\"string_value\"]"),
    ])
  let specification_filters = [
    BasicType("string_key", accepted_types.String),
    BasicType("int_key", accepted_types.Integer),
    BasicType("decimal_key", accepted_types.Decimal),
    BasicType("boolean_key", accepted_types.Boolean),
    BasicType(
      "list_string_key",
      accepted_types.List(accepted_types.String),
    ),
  ]

  let actual =
    linker.resolve_filters(instantiated_filters, specification_filters)

  let expected =
    Ok(
      generic_dictionary.GenericDictionary(
        dict.from_list([
          #(
            "string_key",
            generic_dictionary.TypedValue("string_value", accepted_types.String),
          ),
          #(
            "int_key",
            generic_dictionary.TypedValue("1", accepted_types.Integer),
          ),
          #(
            "decimal_key",
            generic_dictionary.TypedValue("1.1", accepted_types.Decimal),
          ),
          #(
            "boolean_key",
            generic_dictionary.TypedValue("true", accepted_types.Boolean),
          ),
          #(
            "list_string_key",
            generic_dictionary.TypedValue(
              "[\"string_value\"]",
              accepted_types.List(accepted_types.String),
            ),
          ),
        ]),
      ),
    )

  assert actual == expected
}

pub fn resolve_slo_test() {
  let query_template_type_a =
    QueryTemplateType(
      specification_of_query_templates: [
        BasicType("key", accepted_types.String),
      ],
      name: "query_template_type_a",
    )

  let sli_type_a_filters = [
    BasicType("key", accepted_types.String),
  ]

  let service_a_filters =
    dict.from_list([
      #("key", "value"),
    ])

  let service_a_sli_type =
    SliType(
      name: "sli_type_a",
      query_template_type: query_template_type_a,
      specification_of_query_templatized_variables: sli_type_a_filters,
      typed_instatiation_of_query_templates: generic_dictionary.new(),
    )

  let service_a =
    Service(name: "service_a", supported_sli_types: [service_a_sli_type])

  let actual =
    linker.resolve_slo(
      UnresolvedSlo(
        typed_instatiation_of_query_templatized_variables: service_a_filters,
        threshold: 0.9,
        sli_type: "sli_type_a",
        service_name: "service_a",
        window_in_days: 30,
      ),
      [service_a],
    )

  let expected_filters =
    generic_dictionary.GenericDictionary(
      dict.from_list([
        #("key", generic_dictionary.TypedValue("value", accepted_types.String)),
      ]),
    )

  let expected =
    Ok(ast.Slo(
      typed_instatiation_of_query_templatized_variables: expected_filters,
      threshold: 0.9,
      sli_type: "sli_type_a",
      service_name: "service_a",
      window_in_days: 30,
    ))

  assert actual == expected
}

pub fn link_and_validate_instantiation_test() {
  let sli_type_a_filters = [
    BasicType("key", accepted_types.String),
  ]

  let query_template_type_a =
    QueryTemplateType(
      specification_of_query_templates: sli_type_a_filters,
      name: "query_template_type_a",
    )

  let service_a_filters =
    dict.from_list([
      #("key", "value"),
    ])

  let service_a_sli_type =
    SliType(
      name: "sli_type_a",
      query_template_type: query_template_type_a,
      specification_of_query_templatized_variables: sli_type_a_filters,
      typed_instatiation_of_query_templates: generic_dictionary.new(),
    )

  let service_a =
    Service(name: "service_a", supported_sli_types: [service_a_sli_type])

  let actual =
    linker.link_and_validate_instantiation(
      UnresolvedTeam(name: "team_a", slos: [
        UnresolvedSlo(
          typed_instatiation_of_query_templatized_variables: service_a_filters,
          threshold: 0.9,
          sli_type: "sli_type_a",
          service_name: "service_a",
          window_in_days: 30,
        ),
      ]),
      [service_a],
    )

  let expected_filters =
    generic_dictionary.GenericDictionary(
      dict.from_list([
        #("key", generic_dictionary.TypedValue("value", accepted_types.String)),
      ]),
    )

  let expected =
    Ok(
      ast.Team(name: "team_a", slos: [
        ast.Slo(
          typed_instatiation_of_query_templatized_variables: expected_filters,
          threshold: 0.9,
          sli_type: "sli_type_a",
          service_name: "service_a",
          window_in_days: 30,
        ),
      ]),
    )

  assert actual == expected
}
