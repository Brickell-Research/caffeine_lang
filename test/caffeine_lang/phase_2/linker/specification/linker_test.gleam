import caffeine_lang/phase_2/linker/specification/linker
import caffeine_lang/types/ast.{
  QueryTemplateFilter, QueryTemplateType, Service, SliType,
}
import caffeine_lang/types/specification_types.{QueryTemplateTypeUnresolved, ServiceUnresolved, SliTypeUnresolved}
import caffeine_lang/types/accepted_types
import caffeine_lang/types/generic_dictionary
import gleam/dict
import gleam/result

pub fn resolve_unresolved_sli_type_test() {
  let query_template_filters = [
    QueryTemplateFilter(
      attribute_name: "a",
      attribute_type: accepted_types.Integer,
    ),
    QueryTemplateFilter(
      attribute_name: "b",
      attribute_type: accepted_types.Integer,
    ),
  ]
  let query_template =
    QueryTemplateType(
      metric_attributes: query_template_filters,
      name: "good_over_bad",
    )
  let query_template_types = [query_template]

  // Create metric attributes for unresolved SLI type (plain dict)
  let unresolved_metric_attrs = 
    dict.from_list([
      #("numerator_query", "numerator_value"), 
      #("denominator_query", "denominator_value")
    ])

  // Create expected resolved metric attributes (GenericDictionary)
  let expected_metric_attrs = 
    generic_dictionary.from_string_dict(
      unresolved_metric_attrs,
      dict.from_list([
        #("numerator_query", accepted_types.String), 
        #("denominator_query", accepted_types.String)
      ])
    )
    |> result.unwrap(generic_dictionary.new())

  // Create unresolved SLI type with plain dict for metric_attributes
  let unresolved_sli_type = 
    SliTypeUnresolved(
      name: "a", 
      query_template_type: "good_over_bad",
      metric_attributes: unresolved_metric_attrs,
      filters: ["a", "b"]
    )

  // Call the function under test
  let result = 
    linker.resolve_unresolved_sli_type(
      unresolved_sli_type,
      query_template_types,
      query_template_filters,
    )

  // Verify the result
  case result {
    Ok(resolved_sli_type) -> {
      assert resolved_sli_type.name == "a"
      assert resolved_sli_type.query_template_type == query_template
      // Compare the string representations of the metric attributes
      assert generic_dictionary.to_string_dict(resolved_sli_type.metric_attributes) == 
             generic_dictionary.to_string_dict(expected_metric_attrs)
      assert resolved_sli_type.filters == query_template_filters
      True
    }
    Error(_) -> False
  }
}

pub fn resolve_unresolved_sli_type_error_test() {
  let query_template_filters = [
    QueryTemplateFilter(
      attribute_name: "a",
      attribute_type: accepted_types.Integer,
    ),
    QueryTemplateFilter(
      attribute_name: "b",
      attribute_type: accepted_types.Integer,
    ),
  ]
  let query_template =
    QueryTemplateType(
      metric_attributes: query_template_filters,
      name: "good_over_bad",
    )
  let query_template_types = [query_template]

  // Create test metric attributes as plain dict for unresolved SLI type
  let unresolved_metric_attrs = 
    dict.from_list([
      #("numerator_query", ""), 
      #("denominator_query", "")
    ])

  // Call the function under test
  let result = linker.resolve_unresolved_sli_type(
    SliTypeUnresolved(
      name: "a", 
      query_template_type: "nonexistent_template",
      metric_attributes: unresolved_metric_attrs,
      filters: ["a", "b"]
    ),
    query_template_types,
    query_template_filters,
  )

  // Verify the error message
  assert result == Error("QueryTemplateType nonexistent_template not found")
}

pub fn resolve_unresolved_service_test() {
  // Create a test query template
  let query_template =
    QueryTemplateType(
      metric_attributes: [],
      name: "good_over_bad",
    )
  
  // Create test metric attributes as GenericDictionary for resolved SLI type
  let resolved_metric_attrs = 
    generic_dictionary.from_string_dict(
      dict.from_list([
        #("numerator_query", ""), 
        #("denominator_query", "")
      ]),
      dict.from_list([
        #("numerator_query", accepted_types.String),
        #("denominator_query", accepted_types.String)
      ])
    )
    |> result.unwrap(generic_dictionary.new())
  
  // Create test SLI types
  let sli_type_a = 
    SliType(
      name: "a", 
      query_template_type: query_template,
      metric_attributes: resolved_metric_attrs,
      filters: []
    )
  
  let sli_type_b = 
    SliType(
      name: "b", 
      query_template_type: query_template,
      metric_attributes: resolved_metric_attrs,
      filters: []
    )
  
  let sli_types = [sli_type_a, sli_type_b]
  
  // Call the function under test
  let result = linker.resolve_unresolved_service(
    ServiceUnresolved(name: "test_service", sli_types: ["a", "b"]),
    sli_types,
  )
  
  // Verify the result
  case result {
    Ok(service) -> {
      assert service.name == "test_service"
      case service.supported_sli_types {
        [first, second] -> {
          assert first.name == "a"
          assert second.name == "b"
          True
        }
        _ -> False
      }
    }
    Error(_) -> False
  }
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
      metric_attributes: generic_dictionary.from_string_dict(
    dict.from_list([#("numerator_query", ""), #("denominator_query", "")]),
    dict.from_list([#("numerator_query", accepted_types.String), #("denominator_query", accepted_types.String)])
  )
  |> result.unwrap(generic_dictionary.new()),
      filters: []
    ),
    SliType(
      name: "b", 
      query_template_type: query_template,
      metric_attributes: generic_dictionary.from_string_dict(
    dict.from_list([#("numerator_query", ""), #("denominator_query", "")]),
    dict.from_list([#("numerator_query", accepted_types.String), #("denominator_query", accepted_types.String)])
  )
  |> result.unwrap(generic_dictionary.new()),
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
      attribute_type: accepted_types.Integer,
    )
  let query_template_filter_b =
    QueryTemplateFilter(
      attribute_name: "b",
      attribute_type: accepted_types.Integer,
    )

  let query_template_filters = [
    query_template_filter_a,
    query_template_filter_b,
  ]

  let unresolved_sli_types = [
    SliTypeUnresolved(
      name: "a", 
      query_template_type: "good_over_bad",
      metric_attributes: dict.from_list([
        #("numerator_query", ""), 
        #("denominator_query", "")
      ]),
      filters: ["a", "b"]
    ),
    SliTypeUnresolved(
      name: "b", 
      query_template_type: "good_over_bad",
      metric_attributes: dict.from_list([
        #("numerator_query", ""), 
        #("denominator_query", "")
      ]),
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
      metric_attributes: generic_dictionary.from_string_dict(
    dict.from_list([#("numerator_query", ""), #("denominator_query", "")]),
    dict.from_list([#("numerator_query", accepted_types.String), #("denominator_query", accepted_types.String)])
  )
  |> result.unwrap(generic_dictionary.new()),
      filters: query_template_filters
    ),
    SliType(
      name: "b", 
      query_template_type: resolved_query_template,
      metric_attributes: generic_dictionary.from_string_dict(
    dict.from_list([#("numerator_query", ""), #("denominator_query", "")]),
    dict.from_list([#("numerator_query", accepted_types.String), #("denominator_query", accepted_types.String)])
  )
  |> result.unwrap(generic_dictionary.new()),
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
