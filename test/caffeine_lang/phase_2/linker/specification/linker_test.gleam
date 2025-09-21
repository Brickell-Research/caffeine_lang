import caffeine_lang/common_types/accepted_types
import caffeine_lang/common_types/generic_dictionary
import caffeine_lang/phase_1/types as unresolved_types
import caffeine_lang/phase_2/linker/specification/linker
import caffeine_lang/phase_2/types.{
  BasicType, QueryTemplateType, Service, SliType,
} as ast
import gleam/dict
import gleam/result

pub fn resolve_unresolved_sli_type_test() {
  let basic_types = [
    BasicType(attribute_name: "a", attribute_type: accepted_types.Integer),
    BasicType(attribute_name: "b", attribute_type: accepted_types.Integer),
  ]
  let query_template =
    QueryTemplateType(
      specification_of_query_templates: basic_types,
      name: "good_over_bad",
    )
  let query_template_types = [query_template]

  // Create metric attributes for unresolved SLI type (plain dict)
  let unresolved_metric_attrs =
    dict.from_list([
      #("numerator_query", "numerator_value"),
      #("denominator_query", "denominator_value"),
    ])

  // Create expected resolved metric attributes (GenericDictionary)
  let unresolved_sli_type =
    unresolved_types.SliTypeUnresolved(
      name: "a",
      query_template_type: "good_over_bad",
      typed_instatiation_of_query_templates: unresolved_metric_attrs,
      specification_of_query_templatized_variables: ["a", "b"],
    )

  // Call the function under test
  let result =
    linker.resolve_unresolved_sli_type(
      unresolved_sli_type,
      query_template_types,
      basic_types,
    )

  // Verify the result
  case result {
    Ok(resolved_sli_type) -> {
      // Create expected typed_instatiation_of_query_templates with the correct fields
      let expected_typed_instatiation =
        generic_dictionary.from_string_dict(
          dict.from_list([
            #("numerator_query", "numerator_value"),
            #("denominator_query", "denominator_value"),
          ]),
          dict.from_list([
            #("numerator_query", accepted_types.String),
            #("denominator_query", accepted_types.String),
          ]),
        )
        |> result.unwrap(generic_dictionary.new())

      assert resolved_sli_type.name == "a"
      assert resolved_sli_type.query_template_type == query_template
      // Compare the string representations of the metric attributes
      assert generic_dictionary.to_string_dict(
          resolved_sli_type.typed_instatiation_of_query_templates,
        )
        == generic_dictionary.to_string_dict(expected_typed_instatiation)
      assert resolved_sli_type.specification_of_query_templatized_variables
        == basic_types
      True
    }
    Error(_) -> False
  }
}

pub fn resolve_unresolved_sli_type_error_test() {
  let basic_types = [
    BasicType(attribute_name: "a", attribute_type: accepted_types.Integer),
    BasicType(attribute_name: "b", attribute_type: accepted_types.Integer),
  ]
  let query_template =
    QueryTemplateType(
      specification_of_query_templates: basic_types,
      name: "good_over_bad",
    )
  let query_template_types = [query_template]

  // Create test metric attributes as plain dict for unresolved SLI type
  let unresolved_metric_attrs =
    dict.from_list([#("numerator_query", ""), #("denominator_query", "")])

  // Call the function under test
  let result =
    linker.resolve_unresolved_sli_type(
      unresolved_types.SliTypeUnresolved(
        name: "a",
        query_template_type: "nonexistent_template",
        typed_instatiation_of_query_templates: unresolved_metric_attrs,
        specification_of_query_templatized_variables: ["a", "b"],
      ),
      query_template_types,
      basic_types,
    )

  // Verify the error message
  assert result == Error("QueryTemplateType nonexistent_template not found")
}

pub fn resolve_unresolved_service_test() {
  // Create a test query template
  let query_template =
    QueryTemplateType(
      specification_of_query_templates: [],
      name: "good_over_bad",
    )

  // Create test metric attributes as GenericDictionary for resolved SLI type
  let _expected_metric_attrs =
    generic_dictionary.from_string_dict(
      dict.from_list([
        #("numerator_query", "numerator_value"),
        #("denominator_query", "denominator_value"),
      ]),
      dict.from_list([
        #("numerator_query", accepted_types.String),
        #("denominator_query", accepted_types.String),
      ]),
    )
    |> result.unwrap(generic_dictionary.new())

  // Create test SLI types
  let expected_sli_type =
    SliType(
      name: "a",
      query_template_type: query_template,
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([#("numerator_query", ""), #("denominator_query", "")]),
        dict.from_list([
          #("numerator_query", accepted_types.String),
          #("denominator_query", accepted_types.String),
        ]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [],
    )

  let expected_sli_type_b =
    SliType(
      name: "b",
      query_template_type: query_template,
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([#("numerator_query", ""), #("denominator_query", "")]),
        dict.from_list([
          #("numerator_query", accepted_types.String),
          #("denominator_query", accepted_types.String),
        ]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [],
    )

  let sli_types = [expected_sli_type, expected_sli_type_b]

  // Call the function under test
  let result =
    linker.resolve_unresolved_service(
      unresolved_types.ServiceUnresolved(name: "test_service", sli_types: [
        "a",
        "b",
      ]),
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
      specification_of_query_templates: [],
      name: "good_over_bad",
    )
  let xs = [
    SliType(
      name: "a",
      query_template_type: query_template,
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([#("numerator_query", ""), #("denominator_query", "")]),
        dict.from_list([
          #("numerator_query", accepted_types.String),
          #("denominator_query", accepted_types.String),
        ]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [],
    ),
    SliType(
      name: "b",
      query_template_type: query_template,
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([#("numerator_query", ""), #("denominator_query", "")]),
        dict.from_list([
          #("numerator_query", accepted_types.String),
          #("denominator_query", accepted_types.String),
        ]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [],
    ),
  ]

  assert linker.resolve_unresolved_service(
      unresolved_types.ServiceUnresolved(name: "a", sli_types: ["a", "b", "c"]),
      xs,
    )
    == Error("Failed to link sli types to service")
}

pub fn link_and_validate_specification_sub_parts_test() {
  let basic_type_a =
    BasicType(attribute_name: "a", attribute_type: accepted_types.Integer)
  let basic_type_b =
    BasicType(attribute_name: "b", attribute_type: accepted_types.Integer)

  let query_template_filters = [
    basic_type_a,
    basic_type_b,
  ]

  let unresolved_sli_types = [
    unresolved_types.SliTypeUnresolved(
      name: "a",
      query_template_type: "good_over_bad",
      typed_instatiation_of_query_templates: dict.from_list([
        #("numerator_query", ""),
        #("denominator_query", ""),
      ]),
      specification_of_query_templatized_variables: ["a", "b"],
    ),
    unresolved_types.SliTypeUnresolved(
      name: "b",
      query_template_type: "good_over_bad",
      typed_instatiation_of_query_templates: dict.from_list([
        #("numerator_query", ""),
        #("denominator_query", ""),
      ]),
      specification_of_query_templatized_variables: ["a", "b"],
    ),
  ]

  let unresolved_services = [
    unresolved_types.ServiceUnresolved(name: "service_a", sli_types: [
      "a",
      "b",
    ]),
  ]

  let unresolved_query_template_types = [
    unresolved_types.QueryTemplateTypeUnresolved(
      name: "good_over_bad",
      specification_of_query_templates: [
        "a",
        "b",
      ],
    ),
  ]

  let resolved_query_template =
    QueryTemplateType(
      specification_of_query_templates: [basic_type_a, basic_type_b],
      name: "good_over_bad",
    )

  // Create expected typed_instatiation_of_query_templates with the correct fields
  let expected_typed_instatiation =
    generic_dictionary.from_string_dict(
      dict.from_list([#("numerator_query", ""), #("denominator_query", "")]),
      dict.from_list([
        #("numerator_query", accepted_types.String),
        #("denominator_query", accepted_types.String),
      ]),
    )
    |> result.unwrap(generic_dictionary.new())

  let expected_sli_types = [
    ast.SliType(
      name: "a",
      query_template_type: resolved_query_template,
      typed_instatiation_of_query_templates: expected_typed_instatiation,
      specification_of_query_templatized_variables: query_template_filters,
    ),
    SliType(
      name: "b",
      query_template_type: resolved_query_template,
      typed_instatiation_of_query_templates: expected_typed_instatiation,
      specification_of_query_templatized_variables: query_template_filters,
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
