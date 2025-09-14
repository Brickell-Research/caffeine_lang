import caffeine/phase_2/linker
import caffeine/types/intermediate_representation.{
  GoodOverBadQueryTemplate, Integer, Organization, Service, SliFilter, SliType,
  Slo, Team,
}
import caffeine/types/specification_types.{ServiceUnresolved, SliTypeUnresolved}
import gleam/dict
import gleam/list
import gleam/string

pub fn fetch_by_attribute_name_sli_filter_test() {
  let xs = [
    SliFilter(attribute_name: "a", attribute_type: Integer, required: True),
    SliFilter(attribute_name: "b", attribute_type: Integer, required: False),
  ]

  assert linker.fetch_by_attribute_name_sli_filter(xs, "a")
    == Ok(SliFilter(
      attribute_name: "a",
      attribute_type: Integer,
      required: True,
    ))

  assert linker.fetch_by_attribute_name_sli_filter(xs, "c")
    == Error("Attribute c not found")
}

pub fn fetch_by_name_sli_type_test() {
  let query_template = GoodOverBadQueryTemplate(
    numerator_query: "numerator",
    denominator_query: "denominator",
    name: "good_over_bad",
  )
  let xs = [
    SliType(name: "a", filters: [], query_template: query_template),
    SliType(name: "b", filters: [], query_template: query_template),
  ]

  assert linker.fetch_by_name_sli_type(xs, "a")
    == Ok(SliType(name: "a", filters: [], query_template: query_template))

  assert linker.fetch_by_name_sli_type(xs, "c") == Error("SliType c not found")
}

pub fn resolve_unresolved_sli_type_test() {
  let xs = [
    SliFilter(attribute_name: "a", attribute_type: Integer, required: True),
    SliFilter(attribute_name: "b", attribute_type: Integer, required: False),
  ]
  let query_template = GoodOverBadQueryTemplate(
    numerator_query: "numerator",
    denominator_query: "denominator",
    name: "good_over_bad",
  )
  let query_template_types = [query_template]

  assert linker.resolve_unresolved_sli_type(
      SliTypeUnresolved(
        name: "a",
        filters: ["a", "b"],
        query_template_type: "good_over_bad",
      ),
      xs,
      query_template_types,
    )
    == Ok(SliType(name: "a", filters: xs, query_template: query_template))
}

pub fn resolve_unresolved_sli_type_error_test() {
  let xs = [
    SliFilter(attribute_name: "a", attribute_type: Integer, required: True),
    SliFilter(attribute_name: "b", attribute_type: Integer, required: False),
  ]
  let query_template = GoodOverBadQueryTemplate(
    numerator_query: "numerator",
    denominator_query: "denominator",
    name: "good_over_bad",
  )
  let query_template_types = [query_template]

  assert linker.resolve_unresolved_sli_type(
      SliTypeUnresolved(name: "a", query_template_type: "good_over_bad", filters: [
        "a",
        "b",
        "c",
      ]),
      xs,
      query_template_types,
    )
    == Error("Failed to link sli filters to sli type")
}

pub fn resolve_unresolved_service_test() {
  let query_template = GoodOverBadQueryTemplate(
    numerator_query: "numerator",
    denominator_query: "denominator",
    name: "good_over_bad",
  )
  let xs = [
    SliType(name: "a", filters: [], query_template: query_template),
    SliType(name: "b", filters: [], query_template: query_template),
  ]

  assert linker.resolve_unresolved_service(
      ServiceUnresolved(name: "a", sli_types: ["a", "b"]),
      xs,
    )
    == Ok(Service(name: "a", supported_sli_types: xs))
}

pub fn resolve_unresolved_service_error_test() {
  let query_template = GoodOverBadQueryTemplate(
    numerator_query: "numerator",
    denominator_query: "denominator",
    name: "good_over_bad",
  )
  let xs = [
    SliType(name: "a", filters: [], query_template: query_template),
    SliType(name: "b", filters: [], query_template: query_template),
  ]

  assert linker.resolve_unresolved_service(
      ServiceUnresolved(name: "a", sli_types: ["a", "b", "c"]),
      xs,
    )
    == Error("Failed to link sli types to service")
}

pub fn link_and_validate_specification_sub_parts_test() {
  let sli_filter_a =
    SliFilter(attribute_name: "a", attribute_type: Integer, required: True)
  let sli_filter_b =
    SliFilter(attribute_name: "b", attribute_type: Integer, required: False)

  let sli_filters = [
    sli_filter_a,
    sli_filter_b,
  ]

  let unresolved_sli_types = [
    SliTypeUnresolved(name: "a", query_template_type: "good_over_bad", filters: ["a", "b"]),
    SliTypeUnresolved(name: "b", query_template_type: "good_over_bad", filters: ["a"]),
  ]

  let unresolved_services = [
    ServiceUnresolved(name: "service_a", sli_types: [
      "a",
      "b",
    ]),
  ]

  let query_template = GoodOverBadQueryTemplate(
    numerator_query: "numerator",
    denominator_query: "denominator",
    name: "good_over_bad",
  )
  let query_template_types = [query_template]

  let expected_sli_types = [
    SliType(
      name: "a",
      filters: [sli_filter_a, sli_filter_b],
      query_template: query_template,
    ),
    SliType(
      name: "b",
      filters: [sli_filter_a],
      query_template: query_template,
    ),
  ]

  let expected_services = [
    Service(name: "service_a", supported_sli_types: expected_sli_types),
  ]

  assert linker.link_and_validate_specification_sub_parts(
      unresolved_services,
      unresolved_sli_types,
      sli_filters,
      query_template_types,
    )
    == Ok(expected_services)
}

pub fn aggregate_teams_and_slos_test() {
  let slo_a =
    Slo(
      filters: dict.from_list([#("key", "value")]),
      threshold: 0.9,
      sli_type: "sli_type_a",
      service_name: "service_a",
    )

  let slo_b =
    Slo(
      filters: dict.from_list([#("key", "value")]),
      threshold: 0.8,
      sli_type: "sli_type_b",
      service_name: "service_b",
    )

  let slo_c =
    Slo(
      filters: dict.from_list([#("key", "value")]),
      threshold: 0.7,
      sli_type: "sli_type_c",
      service_name: "service_c",
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

pub fn get_instantiation_yaml_files_test() {
  let actual = linker.get_instantiation_yaml_files("./test/artifacts")

  let expected_files = [
    "./test/artifacts/platform/less_reliable_service.yaml",
    "./test/artifacts/platform/reliable_service.yaml",
    "./test/artifacts/platform/reliable_service_invalid_sli_type_type.yaml",
    "./test/artifacts/platform/reliable_service_invalid_threshold_type.yaml",
    "./test/artifacts/platform/reliable_service_missing_filters.yaml",
    "./test/artifacts/platform/reliable_service_missing_sli_type.yaml",
    "./test/artifacts/platform/reliable_service_missing_slos.yaml",
    "./test/artifacts/platform/reliable_service_missing_threshold.yaml",
    "./test/artifacts/platform/simple_yaml_load_test.yaml",
  ]

  case actual {
    Ok(files) -> {
      assert list.sort(files, string.compare)
        == list.sort(expected_files, string.compare)
    }
    Error(_) -> panic as "Failed to read instantiation files"
  }
}

pub fn link_specification_and_instantiation_test() {
  let actual =
    linker.link_specification_and_instantiation(
      "./test/artifacts/some_organization/specifications",
      "./test/artifacts/some_organization",
    )

  let expected_slo_reliable_service =
    intermediate_representation.Slo(
      threshold: 99.5,
      sli_type: "error_rate",
      service_name: "reliable_service",
      filters: dict.from_list([#("number_of_users", "100")]),
    )

  let expected_slo_less_reliable_service =
    intermediate_representation.Slo(
      threshold: 99.5,
      sli_type: "error_rate",
      service_name: "less_reliable_service",
      filters: dict.from_list([#("number_of_users", "100")]),
    )

  let expected_sli_filter =
    SliFilter(
      attribute_name: "number_of_users",
      attribute_type: Integer,
      required: True,
    )

  let expected_sli_type =
    SliType(
      name: "error_rate",
      filters: [expected_sli_filter],
      query_template: GoodOverBadQueryTemplate(
        numerator_query: "sum(rate(http_requests_total{status!~'5..'}[5m]))",
        denominator_query: "sum(rate(http_requests_total[5m]))",
        name: "good_over_bad",
      ),
    )

  let expected =
    Ok(
      Organization(
        service_definitions: [
          Service(name: "reliable_service", supported_sli_types: [
            expected_sli_type,
          ]),
          Service(name: "less_reliable_service", supported_sli_types: [
            expected_sli_type,
          ]),
        ],
        teams: [
          Team(name: "frontend", slos: [expected_slo_less_reliable_service]),
          Team(name: "platform", slos: [expected_slo_reliable_service]),
        ],
      ),
    )

  assert actual == expected
}
