import caffeine/phase_2/linker/specification/linker
import caffeine/types/ast.{
  Integer, QueryTemplateFilter, QueryTemplateType, Service, SliType,
}
import caffeine/types/specification_types.{
  QueryTemplateTypeUnresolved, ServiceUnresolved, SliTypeUnresolved,
}

pub fn resolve_unresolved_sli_type_test() {
  let query_template_filters = [
    QueryTemplateFilter(
      attribute_name: "a",
      attribute_type: Integer,
    ),
    QueryTemplateFilter(
      attribute_name: "b",
      attribute_type: Integer,
    ),
  ]
  let query_template =
    QueryTemplateType(
      metric_attributes: query_template_filters,
      name: "good_over_bad",
    )
  let query_template_types = [query_template]

  assert linker.resolve_unresolved_sli_type(
      SliTypeUnresolved(
        name: "a", 
        query_template_type: "good_over_bad",
        metric_attributes: ["numerator_query", "denominator_query"],
        filters: ["a", "b"]
      ),
      query_template_types,
      query_template_filters,
    )
    == Ok(SliType(
      name: "a", 
      query_template_type: query_template,
      metric_attributes: ["numerator_query", "denominator_query"],
      filters: query_template_filters
    ))
}

pub fn resolve_unresolved_sli_type_error_test() {
  let query_template_filters = [
    QueryTemplateFilter(
      attribute_name: "a",
      attribute_type: Integer,
    ),
    QueryTemplateFilter(
      attribute_name: "b",
      attribute_type: Integer,
    ),
  ]
  let query_template =
    QueryTemplateType(
      metric_attributes: query_template_filters,
      name: "good_over_bad",
    )
  let query_template_types = [query_template]

  assert linker.resolve_unresolved_sli_type(
      SliTypeUnresolved(
        name: "a", 
        query_template_type: "nonexistent_template",
        metric_attributes: ["numerator_query", "denominator_query"],
        filters: ["a", "b"]
      ),
      query_template_types,
      query_template_filters,
    )
    == Error("QueryTemplateType nonexistent_template not found")
}

pub fn resolve_unresolved_service_test() {
  let query_template =
    QueryTemplateType(
      metric_attributes: [],
      name: "good_over_bad",
    )
  let xs = [
    SliType(
      name: "a", 
      query_template_type: query_template,
      metric_attributes: ["numerator_query", "denominator_query"],
      filters: []
    ),
    SliType(
      name: "b", 
      query_template_type: query_template,
      metric_attributes: ["numerator_query", "denominator_query"],
      filters: []
    ),
  ]

  assert linker.resolve_unresolved_service(
      ServiceUnresolved(name: "a", sli_types: ["a", "b"]),
      xs,
    )
    == Ok(Service(name: "a", supported_sli_types: xs))
}

pub fn resolve_unresolved_service_error_test() {
  let query_template =
    QueryTemplateType(
      metric_attributes: [],
      name: "good_over_bad",
    )
  let xs = [
    SliType(
      name: "a", 
      query_template_type: query_template,
      metric_attributes: ["numerator_query", "denominator_query"],
      filters: []
    ),
    SliType(
      name: "b", 
      query_template_type: query_template,
      metric_attributes: ["numerator_query", "denominator_query"],
      filters: []
    ),
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
    )
  let query_template_filter_b =
    QueryTemplateFilter(
      attribute_name: "b",
      attribute_type: Integer,
    )

  let query_template_filters = [
    query_template_filter_a,
    query_template_filter_b,
  ]

  let unresolved_sli_types = [
    SliTypeUnresolved(
      name: "a", 
      query_template_type: "good_over_bad",
      metric_attributes: ["numerator_query", "denominator_query"],
      filters: ["a", "b"]
    ),
    SliTypeUnresolved(
      name: "b", 
      query_template_type: "good_over_bad",
      metric_attributes: ["numerator_query", "denominator_query"],
      filters: ["a", "b"]
    ),
  ]

  let unresolved_services = [
    ServiceUnresolved(name: "service_a", sli_types: [
      "a",
      "b",
    ]),
  ]

  let unresolved_query_template_types = [
    QueryTemplateTypeUnresolved(
      name: "good_over_bad",
      metric_attributes: ["a", "b"],
    ),
  ]

  let resolved_query_template =
    QueryTemplateType(
      metric_attributes: query_template_filters,
      name: "good_over_bad",
    )

  let expected_sli_types = [
    SliType(
      name: "a", 
      query_template_type: resolved_query_template,
      metric_attributes: ["numerator_query", "denominator_query"],
      filters: query_template_filters
    ),
    SliType(
      name: "b", 
      query_template_type: resolved_query_template,
      metric_attributes: ["numerator_query", "denominator_query"],
      filters: query_template_filters
    ),
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
