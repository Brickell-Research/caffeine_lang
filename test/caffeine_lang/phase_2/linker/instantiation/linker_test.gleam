import caffeine_lang/phase_2/linker/instantiation/linker
import caffeine_lang/types/ast/basic_type
import caffeine_lang/types/ast/query_template_type
import caffeine_lang/types/ast/service
import caffeine_lang/types/ast/sli_type
import caffeine_lang/types/ast/slo
import caffeine_lang/types/ast/team
import caffeine_lang/types/common/accepted_types
import caffeine_lang/types/common/generic_dictionary
import caffeine_lang/types/unresolved/unresolved_slo
import caffeine_lang/types/unresolved/unresolved_team
import cql/parser.{ExpContainer, Primary, PrimaryWord, Word}
import gleam/dict
import gleam/list
import gleam/string
import gleamy_spec/gleeunit

// ==== Test Helpers ====
fn create_test_dictionary() -> generic_dictionary.GenericDictionary {
  let values = dict.from_list([#("key", "value")])
  let type_defs = dict.from_list([#("key", accepted_types.String)])
  case generic_dictionary.from_string_dict(values, type_defs) {
    Ok(d) -> d
    Error(_) -> generic_dictionary.new()
  }
}

fn slo_creator(name: String, sli_type: String, service_name: String) -> slo.Slo {
  slo.Slo(
    name: name,
    typed_instatiation_of_query_templatized_variables: create_test_dictionary(),
    threshold: 0.9,
    sli_type: sli_type,
    service_name: service_name,
    window_in_days: 30,
  )
}

// =================================================

// ==== Tests ====
pub fn aggregate_teams_and_slos_test() {
  let slo_a = slo_creator("slo_a", "sli_type_a", "service_a")
  let slo_b = slo_creator("slo_b", "sli_type_b", "service_b")
  let slo_c = slo_creator("slo_c", "sli_type_c", "service_c")

  let team_a_service_a = team.Team(name: "team_a", slos: [slo_a])
  let team_a_service_b = team.Team(name: "team_a", slos: [slo_b])
  let team_b_service_c = team.Team(name: "team_b", slos: [slo_c])

  let teams = [team_a_service_a, team_a_service_b, team_b_service_c]

  let actual = linker.aggregate_teams_and_slos(teams)

  let expected = [
    team.Team(name: "team_a", slos: [slo_b, slo_a]),
    team.Team(name: "team_b", slos: [slo_c]),
  ]

  list.sort(actual, fn(a, b) { string.compare(a.name, b.name) })
  |> gleeunit.equal(
    list.sort(expected, fn(a, b) { string.compare(a.name, b.name) }),
  )
}

pub fn link_and_validate_instantiation_test() {
  let sli_type_a_filters = [
    basic_type.BasicType("key", accepted_types.String),
  ]

  let query_template_type_a =
    query_template_type.QueryTemplateType(
      specification_of_query_templates: sli_type_a_filters,
      name: "query_template_type_a",
      query: ExpContainer(Primary(PrimaryWord(Word("")))),
    )

  let service_a_filters =
    dict.from_list([
      #("key", "value"),
    ])

  let service_a_sli_type =
    sli_type.SliType(
      name: "sli_type_a",
      query_template_type: query_template_type_a,
      specification_of_query_templatized_variables: sli_type_a_filters,
      typed_instatiation_of_query_templates: generic_dictionary.new(),
    )

  let service_a =
    service.Service(name: "service_a", supported_sli_types: [
      service_a_sli_type,
    ])

  let actual =
    linker.link_and_validate_instantiation(
      unresolved_team.Team(name: "team_a", slos: [
        unresolved_slo.Slo(
          name: "test_slo",
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
      team.Team(name: "team_a", slos: [
        slo.Slo(
          name: "test_slo",
          typed_instatiation_of_query_templatized_variables: expected_filters,
          threshold: 0.9,
          sli_type: "sli_type_a",
          service_name: "service_a",
          window_in_days: 30,
        ),
      ]),
    )

  actual
  |> gleeunit.equal(expected)
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
    basic_type.BasicType("string_key", accepted_types.String),
    basic_type.BasicType("int_key", accepted_types.Integer),
    basic_type.BasicType("decimal_key", accepted_types.Decimal),
    basic_type.BasicType("boolean_key", accepted_types.Boolean),
    basic_type.BasicType(
      "list_string_key",
      accepted_types.NonEmptyList(accepted_types.String),
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
              accepted_types.NonEmptyList(accepted_types.String),
            ),
          ),
        ]),
      ),
    )

  actual
  |> gleeunit.equal(expected)
}

pub fn resolve_slo_test() {
  let query_template_type_a =
    query_template_type.QueryTemplateType(
      specification_of_query_templates: [
        basic_type.BasicType("key", accepted_types.String),
      ],
      name: "query_template_type_a",
      query: ExpContainer(Primary(PrimaryWord(Word("")))),
    )

  let sli_type_a_filters = [
    basic_type.BasicType("key", accepted_types.String),
  ]

  let service_a_filters =
    dict.from_list([
      #("key", "value"),
    ])

  let service_a_sli_type =
    sli_type.SliType(
      name: "sli_type_a",
      query_template_type: query_template_type_a,
      specification_of_query_templatized_variables: sli_type_a_filters,
      typed_instatiation_of_query_templates: generic_dictionary.new(),
    )

  let service_a =
    service.Service(name: "service_a", supported_sli_types: [
      service_a_sli_type,
    ])

  let actual =
    linker.resolve_slo(
      unresolved_slo.Slo(
        name: "test_slo",
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
    Ok(slo.Slo(
      name: "test_slo",
      typed_instatiation_of_query_templatized_variables: expected_filters,
      threshold: 0.9,
      sli_type: "sli_type_a",
      service_name: "service_a",
      window_in_days: 30,
    ))

  actual
  |> gleeunit.equal(expected)
}
