import caffeine/phase_2/linker/specification/linker
import caffeine/types/intermediate_representation.{
  GoodOverBadQueryTemplate, Integer, QueryTemplateFilter, Service, SliType,
}
import caffeine/types/specification_types.{
  GoodOverBadQueryTemplateUnresolved, ServiceUnresolved, SliTypeUnresolved,
}

pub fn resolve_unresolved_sli_type_test() {
  let query_template_filters = [
    QueryTemplateFilter(
      attribute_name: "a",
      attribute_type: Integer,
      required: True,
    ),
    QueryTemplateFilter(
      attribute_name: "b",
      attribute_type: Integer,
      required: False,
    ),
  ]
  let query_template =
    GoodOverBadQueryTemplate(
      numerator_query: "numerator",
      denominator_query: "denominator",
      filters: query_template_filters,
    )
  let query_template_types = [query_template]

  assert linker.resolve_unresolved_sli_type(
      SliTypeUnresolved(name: "a", query_template_type: "good_over_bad"),
      query_template_types,
    )
    == Ok(SliType(name: "a", query_template: query_template))
}

pub fn resolve_unresolved_sli_type_error_test() {
  let query_template_filters = [
    QueryTemplateFilter(
      attribute_name: "a",
      attribute_type: Integer,
      required: True,
    ),
    QueryTemplateFilter(
      attribute_name: "b",
      attribute_type: Integer,
      required: False,
    ),
  ]
  let query_template =
    GoodOverBadQueryTemplate(
      numerator_query: "numerator",
      denominator_query: "denominator",
      filters: query_template_filters,
    )
  let query_template_types = [query_template]

  assert linker.resolve_unresolved_sli_type(
      SliTypeUnresolved(name: "a", query_template_type: "nonexistent_template"),
      query_template_types,
    )
    == Error("QueryTemplateType nonexistent_template not found")
}

pub fn resolve_unresolved_service_test() {
  let query_template =
    GoodOverBadQueryTemplate(
      numerator_query: "numerator",
      denominator_query: "denominator",
      filters: [],
    )
  let xs = [
    SliType(name: "a", query_template: query_template),
    SliType(name: "b", query_template: query_template),
  ]

  assert linker.resolve_unresolved_service(
      ServiceUnresolved(name: "a", sli_types: ["a", "b"]),
      xs,
    )
    == Ok(Service(name: "a", supported_sli_types: xs))
}

pub fn resolve_unresolved_service_error_test() {
  let query_template =
    GoodOverBadQueryTemplate(
      numerator_query: "numerator",
      denominator_query: "denominator",
      filters: [],
    )
  let xs = [
    SliType(name: "a", query_template: query_template),
    SliType(name: "b", query_template: query_template),
  ]

  assert linker.resolve_unresolved_service(
      ServiceUnresolved(name: "a", sli_types: ["a", "b", "c"]),
      xs,
    )
    == Error("Failed to link sli types to service")
}

pub fn link_and_validate_specification_sub_parts_test() {
  let query_template_filter_a =
    QueryTemplateFilter(
      attribute_name: "a",
      attribute_type: Integer,
      required: True,
    )
  let query_template_filter_b =
    QueryTemplateFilter(
      attribute_name: "b",
      attribute_type: Integer,
      required: False,
    )

  let query_template_filters = [
    query_template_filter_a,
    query_template_filter_b,
  ]

  let unresolved_sli_types = [
    SliTypeUnresolved(name: "a", query_template_type: "good_over_bad"),
    SliTypeUnresolved(name: "b", query_template_type: "good_over_bad"),
  ]

  let unresolved_services = [
    ServiceUnresolved(name: "service_a", sli_types: [
      "a",
      "b",
    ]),
  ]

  let unresolved_query_template_types = [
    GoodOverBadQueryTemplateUnresolved(
      numerator_query: "numerator",
      denominator_query: "denominator",
      filters: ["a", "b"],
    ),
  ]

  let resolved_query_template =
    GoodOverBadQueryTemplate(
      numerator_query: "numerator",
      denominator_query: "denominator",
      filters: query_template_filters,
    )

  let expected_sli_types = [
    SliType(name: "a", query_template: resolved_query_template),
    SliType(name: "b", query_template: resolved_query_template),
  ]

  let expected_services = [
    Service(name: "service_a", supported_sli_types: expected_sli_types),
  ]

  assert linker.link_and_validate_specification_sub_parts(
      unresolved_services,
      unresolved_sli_types,
      query_template_filters,
      unresolved_query_template_types,
    )
    == Ok(expected_services)
}
