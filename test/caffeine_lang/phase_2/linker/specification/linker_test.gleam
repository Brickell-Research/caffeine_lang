import caffeine_lang/phase_1/parser/unresolved_query_template_type
import caffeine_lang/phase_1/parser/unresolved_service
import caffeine_lang/phase_1/parser/unresolved_sli_type
import caffeine_lang/phase_2/linker/basic_type
import caffeine_lang/phase_2/linker/query_template_type
import caffeine_lang/phase_2/linker/service
import caffeine_lang/phase_2/linker/sli_type
import caffeine_lang/phase_2/linker/specification/linker
import caffeine_lang/types/accepted_types
import caffeine_lang/types/generic_dictionary
import caffeine_query_language/parser
import deps/gleamy_spec/extensions.{describe, it}
import deps/gleamy_spec/gleeunit
import gleam/dict
import gleam/result

pub fn linker_test() {
  describe("linker", fn() {
    it("should resolve unresolved sli type", fn() {
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
          query: parser.ExpContainer(
            parser.Primary(parser.PrimaryWord(parser.Word(""))),
          ),
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
          |> gleeunit.equal("a")
          resolved_sli_type.query_template_type
          |> gleeunit.equal(query_template)
          // Compare the string representations of the metric attributes
          generic_dictionary.to_string_dict(
            resolved_sli_type.typed_instatiation_of_query_templates,
          )
          |> gleeunit.equal(generic_dictionary.to_string_dict(
            expected_typed_instatiation,
          ))
          resolved_sli_type.specification_of_query_templatized_variables
          |> gleeunit.equal(basic_types)
        }
        Error(err) ->
          err
          |> gleeunit.equal("Should not fail")
      }
    })

    it(
      "should return an error when resolving unresolved sli type with nonexistent template",
      fn() {
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
            query: parser.ExpContainer(
              parser.Primary(parser.PrimaryWord(parser.Word(""))),
            ),
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
        |> gleeunit.equal(Error(
          "QueryTemplateType nonexistent_template not found",
        ))
      },
    )

    it("should resolve unresolved service", fn() {
      // Create a test query template
      let query_template =
        query_template_type.QueryTemplateType(
          specification_of_query_templates: [],
          name: "good_over_bad",
          query: parser.ExpContainer(
            parser.Primary(parser.PrimaryWord(parser.Word(""))),
          ),
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
        )

      let expected_sli_type_b =
        sli_type.SliType(
          name: "b",
          query_template_type: query_template,
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
          |> gleeunit.equal("test_service")
          case service.supported_sli_types {
            [first, second] -> {
              first.name
              |> gleeunit.equal("a")
              second.name
              |> gleeunit.equal("b")
            }
            _ ->
              service.supported_sli_types
              |> gleeunit.equal([])
          }
        }
        Error(err) ->
          err
          |> gleeunit.equal("Should not fail")
      }
    })

    it(
      "should return an error when resolving unresolved service with missing sli types",
      fn() {
        let query_template =
          query_template_type.QueryTemplateType(
            specification_of_query_templates: [],
            name: "good_over_bad",
            query: parser.ExpContainer(
              parser.Primary(parser.PrimaryWord(parser.Word(""))),
            ),
          )
        let xs = [
          sli_type.SliType(
            name: "a",
            query_template_type: query_template,
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
          sli_type.SliType(
            name: "b",
            query_template_type: query_template,
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
        ]

        assert linker.resolve_unresolved_service(
            unresolved_service.Service(name: "a", sli_types: ["a", "b", "c"]),
            xs,
          )
          == Error("Failed to link sli types to service")
      },
    )

    it("should link and validate specification sub parts", fn() {
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
          query: parser.ExpContainer(
            parser.Primary(parser.PrimaryWord(parser.Word(""))),
          ),
        ),
      ]

      let resolved_query_template =
        query_template_type.QueryTemplateType(
          specification_of_query_templates: [basic_type_a, basic_type_b],
          name: "good_over_bad",
          query: parser.ExpContainer(
            parser.Primary(parser.PrimaryWord(parser.Word(""))),
          ),
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
        service.Service(
          name: "service_a",
          supported_sli_types: expected_sli_types,
        ),
      ]

      assert linker.link_and_validate_specification_sub_parts(
          unresolved_services,
          unresolved_sli_types,
          query_template_filters,
          unresolved_query_template_types,
        )
        == Ok(expected_services)
    })
  })
}
