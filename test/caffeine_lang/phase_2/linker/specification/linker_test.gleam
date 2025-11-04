import caffeine_lang/phase_2/linker/specification/linker
import caffeine_lang/types/ast/basic_type
import caffeine_lang/types/ast/query_template_type
import caffeine_lang/types/ast/service
import caffeine_lang/types/ast/sli_type
import caffeine_lang/types/common/accepted_types
import caffeine_lang/types/common/generic_dictionary
import caffeine_lang/types/unresolved/unresolved_query_template_type
import caffeine_lang/types/unresolved/unresolved_service
import caffeine_lang/types/unresolved/unresolved_sli_type
import cql/parser.{ExpContainer, Primary, PrimaryWord, Word}
import gleam/dict
import gleam/result
import gleeunit/should

pub fn resolve_unresolved_sli_type_test() {
  let basic_types = [
    basic_type.BasicType(
      attribute_name: "a",
      attribute_type: accepted_types.Integer,
    ),
    basic_type.BasicType(
      attribute_name: "b",
      attribute_type: accepted_types.Integer,
    ),
  ]
  let query_template =
    query_template_type.QueryTemplateType(
      specification_of_query_templates: basic_types,
      name: "good_over_bad",
      query: ExpContainer(Primary(PrimaryWord(Word("")))),
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
    unresolved_sli_type.SliType(
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

      resolved_sli_type.name
      |> should.equal("a")
      resolved_sli_type.query_template_type
      |> should.equal(query_template)
      // Compare the string representations of the metric attributes
      generic_dictionary.to_string_dict(
        resolved_sli_type.typed_instatiation_of_query_templates,
      )
      |> should.equal(generic_dictionary.to_string_dict(
        expected_typed_instatiation,
      ))
      resolved_sli_type.specification_of_query_templatized_variables
      |> should.equal(basic_types)
    }
    Error(err) ->
      err
      |> should.equal("Should not fail")
  }
}

pub fn resolve_unresolved_sli_type_error_test() {
  let basic_types = [
    basic_type.BasicType(
      attribute_name: "a",
      attribute_type: accepted_types.Integer,
    ),
    basic_type.BasicType(
      attribute_name: "b",
      attribute_type: accepted_types.Integer,
    ),
  ]
  let query_template =
    query_template_type.QueryTemplateType(
      specification_of_query_templates: basic_types,
      name: "good_over_bad",
      query: ExpContainer(Primary(PrimaryWord(Word("")))),
    )
  let query_template_types = [query_template]

  // Create test metric attributes as plain dict for unresolved SLI type
  let unresolved_metric_attrs =
    dict.from_list([#("numerator_query", ""), #("denominator_query", "")])

  // Call the function under test
  let result =
    linker.resolve_unresolved_sli_type(
      unresolved_sli_type.SliType(
        name: "a",
        query_template_type: "nonexistent_template",
        typed_instatiation_of_query_templates: unresolved_metric_attrs,
        specification_of_query_templatized_variables: ["a", "b"],
      ),
      query_template_types,
      basic_types,
    )

  // Verify the error message
  result
  |> should.equal(Error("QueryTemplateType nonexistent_template not found"))
}

pub fn resolve_unresolved_service_test() {
  // Create a test query template
  let query_template =
    query_template_type.QueryTemplateType(
      specification_of_query_templates: [],
      name: "good_over_bad",
      query: ExpContainer(Primary(PrimaryWord(Word("")))),
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
    sli_type.SliType(
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
    sli_type.SliType(
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
      unresolved_service.Service(name: "test_service", sli_types: [
        "a",
        "b",
      ]),
      sli_types,
    )

  // Verify the result
  case result {
    Ok(service) -> {
      service.name
      |> should.equal("test_service")
      case service.supported_sli_types {
        [first, second] -> {
          first.name
          |> should.equal("a")
          second.name
          |> should.equal("b")
        }
        _ ->
          service.supported_sli_types
          |> should.equal([])
      }
    }
    Error(err) ->
      err
      |> should.equal("Should not fail")
  }
}

pub fn resolve_unresolved_service_error_test() {
  let query_template =
    query_template_type.QueryTemplateType(
      specification_of_query_templates: [],
      name: "good_over_bad",
      query: ExpContainer(Primary(PrimaryWord(Word("")))),
    )
  let xs = [
    sli_type.SliType(
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
    sli_type.SliType(
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
      unresolved_service.Service(name: "a", sli_types: ["a", "b", "c"]),
      xs,
    )
    == Error("Failed to link sli types to service")
}

pub fn link_and_validate_specification_sub_parts_test() {
  let basic_type_a =
    basic_type.BasicType(
      attribute_name: "a",
      attribute_type: accepted_types.Integer,
    )
  let basic_type_b =
    basic_type.BasicType(
      attribute_name: "b",
      attribute_type: accepted_types.Integer,
    )

  let query_template_filters = [
    basic_type_a,
    basic_type_b,
  ]

  let unresolved_sli_types = [
    unresolved_sli_type.SliType(
      name: "a",
      query_template_type: "good_over_bad",
      typed_instatiation_of_query_templates: dict.from_list([
        #("numerator_query", ""),
        #("denominator_query", ""),
      ]),
      specification_of_query_templatized_variables: ["a", "b"],
    ),
    unresolved_sli_type.SliType(
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
    unresolved_service.Service(name: "service_a", sli_types: [
      "a",
      "b",
    ]),
  ]

  let unresolved_query_template_types = [
    unresolved_query_template_type.QueryTemplateType(
      name: "good_over_bad",
      specification_of_query_templates: [
        "a",
        "b",
      ],
      query: ExpContainer(Primary(PrimaryWord(Word("")))),
    ),
  ]

  let resolved_query_template =
    query_template_type.QueryTemplateType(
      specification_of_query_templates: [basic_type_a, basic_type_b],
      name: "good_over_bad",
      query: ExpContainer(Primary(PrimaryWord(Word("")))),
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
    sli_type.SliType(
      name: "a",
      query_template_type: resolved_query_template,
      typed_instatiation_of_query_templates: expected_typed_instatiation,
      specification_of_query_templatized_variables: query_template_filters,
    ),
    sli_type.SliType(
      name: "b",
      query_template_type: resolved_query_template,
      typed_instatiation_of_query_templates: expected_typed_instatiation,
      specification_of_query_templatized_variables: query_template_filters,
    ),
  ]

  let expected_services = [
    service.Service(name: "service_a", supported_sli_types: expected_sli_types),
  ]

  assert linker.link_and_validate_specification_sub_parts(
      unresolved_services,
      unresolved_sli_types,
      query_template_filters,
      unresolved_query_template_types,
    )
    == Ok(expected_services)
}
