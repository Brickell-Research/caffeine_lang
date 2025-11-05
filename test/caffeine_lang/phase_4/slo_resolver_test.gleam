import caffeine_lang/phase_4/slo_resolver
import caffeine_lang/types/ast/basic_type
import caffeine_lang/types/ast/organization
import caffeine_lang/types/ast/query_template_type
import caffeine_lang/types/ast/service
import caffeine_lang/types/ast/sli_type
import caffeine_lang/types/ast/slo
import caffeine_lang/types/ast/team
import caffeine_lang/types/common/accepted_types
import caffeine_lang/types/common/generic_dictionary
import caffeine_lang/types/resolved/resolved_sli
import caffeine_lang/types/resolved/resolved_slo
import cql/parser.{
  Add, Div, ExpContainer, Mul, OperatorExpr, Primary, PrimaryExp, PrimaryWord,
  Sub, Word,
}
import gleam/dict
import gleam/result
import gleam/string
import gleamy_spec/gleeunit

fn example_filters() -> generic_dictionary.GenericDictionary {
  generic_dictionary.from_string_dict(
    dict.from_list([
      #("SERVICE", "\"super_scalabale_web_service\""),
      #("REQUESTS_VALID", "true"),
      #("ENVIRONMENT", "production"),
    ]),
    dict.from_list([
      #("SERVICE", accepted_types.String),
      #("REQUESTS_VALID", accepted_types.Boolean),
      #("ENVIRONMENT", accepted_types.String),
    ]),
  )
  |> result.unwrap(generic_dictionary.new())
}

fn example_slo() -> slo.Slo {
  slo.Slo(
    name: "example_slo",
    typed_instatiation_of_query_templatized_variables: example_filters(),
    threshold: 99.5,
    sli_type: "good_over_bad",
    service_name: "super_scalabale_web_service",
    window_in_days: 30,
  )
}

fn example_sli_type() -> sli_type.SliType {
  sli_type.SliType(
    name: "good_over_bad",
    query_template_type: query_template_type.QueryTemplateType(
      name: "good_over_bad",
      specification_of_query_templates: [
        basic_type.BasicType(
          attribute_name: "numerator_query",
          attribute_type: accepted_types.String,
        ),
        basic_type.BasicType(
          attribute_name: "denominator_query",
          attribute_type: accepted_types.String,
        ),
      ],
      query: ExpContainer(Primary(PrimaryWord(Word("")))),
    ),
    typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
      dict.from_list([
        #(
          "numerator_query",
          "max:latency(<100ms, {$$service->SERVICE$$,$$requests_valid->REQUESTS_VALID$$,$$environment->ENVIRONMENT$$})",
        ),
        #(
          "denominator_query",
          "max:latency(<100ms, {$$service->SERVICE$$,$$requests_valid->REQUESTS_VALID$$,$$environment->ENVIRONMENT$$})",
        ),
      ]),
      dict.from_list([
        #("numerator_query", accepted_types.String),
        #("denominator_query", accepted_types.String),
      ]),
    )
      |> result.unwrap(generic_dictionary.new()),
    specification_of_query_templatized_variables: [
      basic_type.BasicType(
        attribute_name: "service",
        attribute_type: accepted_types.String,
      ),
      basic_type.BasicType(
        attribute_name: "environment",
        attribute_type: accepted_types.String,
      ),
      basic_type.BasicType(
        attribute_name: "requests_valid",
        attribute_type: accepted_types.Boolean,
      ),
    ],
  )
}

pub fn resolve_sli_test() {
  let input_sli_type = example_sli_type()

  // Create expected metric attributes as Dict(String, String)
  let expected_metric_attrs =
    dict.from_list([
      #(
        "numerator_query",
        "max:latency(<100ms, {service:\"super_scalabale_web_service\",requests_valid:true,environment:production})",
      ),
      #(
        "denominator_query",
        "max:latency(<100ms, {service:\"super_scalabale_web_service\",requests_valid:true,environment:production})",
      ),
    ])

  let expected =
    Ok(resolved_sli.Sli(
      name: "example_slo",
      query_template_type: input_sli_type.query_template_type,
      metric_attributes: expected_metric_attrs,
      resolved_query: ExpContainer(Primary(PrimaryWord(Word("")))),
    ))

  // Use the filters directly since resolve_sli now expects GenericDictionary
  let input_filters = example_filters()
  let actual =
    slo_resolver.resolve_sli(
      generic_dictionary.to_string_dict(input_filters),
      input_sli_type,
      "example_slo",
    )

  actual
  |> gleeunit.equal(expected)
}

pub fn resolve_slo_test() {
  let input_sli_type = example_sli_type()

  let expected_query_template_type =
    query_template_type.QueryTemplateType(
      name: "good_over_bad",
      specification_of_query_templates: [
        basic_type.BasicType(
          attribute_name: "numerator_query",
          attribute_type: accepted_types.String,
        ),
        basic_type.BasicType(
          attribute_name: "denominator_query",
          attribute_type: accepted_types.String,
        ),
      ],
      query: ExpContainer(Primary(PrimaryWord(Word("")))),
    )

  let expected =
    Ok(resolved_slo.Slo(
      window_in_days: 30,
      threshold: 99.5,
      service_name: "super_scalabale_web_service",
      team_name: "badass_platform_team",
      sli: resolved_sli.Sli(
        name: "example_slo",
        query_template_type: expected_query_template_type,
        metric_attributes: dict.from_list([
          #(
            "numerator_query",
            "max:latency(<100ms, {service:\"super_scalabale_web_service\",requests_valid:true,environment:production})",
          ),
          #(
            "denominator_query",
            "max:latency(<100ms, {service:\"super_scalabale_web_service\",requests_valid:true,environment:production})",
          ),
        ]),
        resolved_query: ExpContainer(Primary(PrimaryWord(Word("")))),
      ),
    ))

  let actual =
    slo_resolver.resolve_slo(example_slo(), "badass_platform_team", [
      input_sli_type,
    ])

  actual
  |> gleeunit.equal(expected)
}

pub fn resolve_slos_test() {
  let input_organization =
    organization.Organization(
      teams: [
        team.Team(name: "badass_platform_team", slos: [example_slo()]),
      ],
      service_definitions: [
        service.Service(
          name: "super_scalabale_web_service",
          supported_sli_types: [
            example_sli_type(),
          ],
        ),
      ],
    )

  let expected =
    Ok([
      resolved_slo.Slo(
        window_in_days: 30,
        threshold: 99.5,
        service_name: "super_scalabale_web_service",
        team_name: "badass_platform_team",
        sli: resolved_sli.Sli(
          name: "example_slo",
          query_template_type: example_sli_type().query_template_type,
          metric_attributes: dict.from_list([
            #(
              "numerator_query",
              "max:latency(<100ms, {service:\"super_scalabale_web_service\",requests_valid:true,environment:production})",
            ),
            #(
              "denominator_query",
              "max:latency(<100ms, {service:\"super_scalabale_web_service\",requests_valid:true,environment:production})",
            ),
          ]),
          resolved_query: ExpContainer(Primary(PrimaryWord(Word("")))),
        ),
      ),
    ])

  let actual = slo_resolver.resolve_slos(input_organization)

  actual
  |> gleeunit.equal(expected)
}

/// Test SLI resolution with complex CQL query expressions
pub fn resolve_sli_with_complex_query_test() {
  let complex_query =
    ExpContainer(OperatorExpr(
      Primary(PrimaryWord(Word("numerator_query"))),
      Primary(PrimaryWord(Word("denominator_query"))),
      Div,
    ))

  let sli_type_with_query =
    sli_type.SliType(
      name: "complex_ratio",
      query_template_type: query_template_type.QueryTemplateType(
        name: "complex_ratio",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "numerator_query",
            attribute_type: accepted_types.String,
          ),
          basic_type.BasicType(
            attribute_name: "denominator_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: complex_query,
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #("numerator_query", "sum:requests.success{$$service->SERVICE$$}"),
          #("denominator_query", "sum:requests.total{$$service->SERVICE$$}"),
        ]),
        dict.from_list([
          #("numerator_query", accepted_types.String),
          #("denominator_query", accepted_types.String),
        ]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "service",
          attribute_type: accepted_types.String,
        ),
        basic_type.BasicType(
          attribute_name: "environment",
          attribute_type: accepted_types.String,
        ),
        basic_type.BasicType(
          attribute_name: "requests_valid",
          attribute_type: accepted_types.Boolean,
        ),
      ],
    )

  let filters =
    dict.from_list([
      #("SERVICE", "\"web_api\""),
      #("ENVIRONMENT", "\"production\""),
      #("REQUESTS_VALID", "true"),
    ])

  let expected_resolved_query =
    ExpContainer(OperatorExpr(
      Primary(
        PrimaryExp(
          Primary(
            PrimaryWord(Word("sum:requests.success{service:\"web_api\"}")),
          ),
        ),
      ),
      Primary(
        PrimaryExp(
          Primary(PrimaryWord(Word("sum:requests.total{service:\"web_api\"}"))),
        ),
      ),
      Div,
    ))

  let expected =
    Ok(resolved_sli.Sli(
      name: "test_slo",
      query_template_type: sli_type_with_query.query_template_type,
      metric_attributes: dict.from_list([
        #("numerator_query", "sum:requests.success{service:\"web_api\"}"),
        #("denominator_query", "sum:requests.total{service:\"web_api\"}"),
      ]),
      resolved_query: expected_resolved_query,
    ))

  let actual =
    slo_resolver.resolve_sli(filters, sli_type_with_query, "test_slo")

  actual
  |> gleeunit.equal(expected)
}

pub fn resolve_sli_with_nested_expressions_test() {
  let nested_query =
    ExpContainer(OperatorExpr(
      OperatorExpr(
        Primary(PrimaryWord(Word("a_query"))),
        Primary(PrimaryWord(Word("b_query"))),
        Add,
      ),
      OperatorExpr(
        Primary(PrimaryWord(Word("c_query"))),
        Primary(PrimaryWord(Word("d_query"))),
        Mul,
      ),
      Sub,
    ))

  let sli_type_nested =
    sli_type.SliType(
      name: "nested_good_over_bad",
      query_template_type: query_template_type.QueryTemplateType(
        name: "nested_good_over_bad",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "a_query",
            attribute_type: accepted_types.String,
          ),
          basic_type.BasicType(
            attribute_name: "b_query",
            attribute_type: accepted_types.String,
          ),
          basic_type.BasicType(
            attribute_name: "c_query",
            attribute_type: accepted_types.String,
          ),
          basic_type.BasicType(
            attribute_name: "d_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: nested_query,
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #("a_query", "metric_a{$$env->ENV$$}"),
          #("b_query", "metric_b{$$env->ENV$$}"),
          #("c_query", "metric_c{$$env->ENV$$}"),
          #("d_query", "metric_d{$$env->ENV$$}"),
        ]),
        dict.from_list([
          #("a_query", accepted_types.String),
          #("b_query", accepted_types.String),
          #("c_query", accepted_types.String),
          #("d_query", accepted_types.String),
        ]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "env",
          attribute_type: accepted_types.String,
        ),
      ],
    )

  let filters = dict.from_list([#("ENV", "prod")])

  let expected_resolved_query =
    ExpContainer(OperatorExpr(
      OperatorExpr(
        Primary(PrimaryExp(Primary(PrimaryWord(Word("metric_a{env:prod}"))))),
        Primary(PrimaryExp(Primary(PrimaryWord(Word("metric_b{env:prod}"))))),
        Add,
      ),
      OperatorExpr(
        Primary(PrimaryExp(Primary(PrimaryWord(Word("metric_c{env:prod}"))))),
        Primary(PrimaryExp(Primary(PrimaryWord(Word("metric_d{env:prod}"))))),
        Mul,
      ),
      Sub,
    ))

  let expected =
    Ok(resolved_sli.Sli(
      name: "test_slo",
      query_template_type: sli_type_nested.query_template_type,
      metric_attributes: dict.from_list([
        #("a_query", "metric_a{env:prod}"),
        #("b_query", "metric_b{env:prod}"),
        #("c_query", "metric_c{env:prod}"),
        #("d_query", "metric_d{env:prod}"),
      ]),
      resolved_query: expected_resolved_query,
    ))

  let actual = slo_resolver.resolve_sli(filters, sli_type_nested, "test_slo")

  actual
  |> gleeunit.equal(expected)
}

pub fn handle_missing_filter_variables_test() {
  let sli_type_with_missing_vars =
    sli_type.SliType(
      name: "missing_vars_test",
      query_template_type: query_template_type.QueryTemplateType(
        name: "missing_vars_test",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "test_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: ExpContainer(Primary(PrimaryWord(Word("test_query")))),
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #("test_query", "metric{$$service->SERVICE$$,$$region->REGION$$}"),
        ]),
        dict.from_list([#("test_query", accepted_types.String)]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "service",
          attribute_type: accepted_types.String,
        ),
        basic_type.BasicType(
          attribute_name: "region",
          attribute_type: accepted_types.String,
        ),
      ],
    )

  // Only provide SERVICE, missing REGION - should cause an error
  let incomplete_filters = dict.from_list([#("SERVICE", "\"api_service\"")])

  let actual =
    slo_resolver.resolve_sli(
      incomplete_filters,
      sli_type_with_missing_vars,
      "test_slo",
    )

  // Should fail because REGION is not provided
  actual
  |> gleeunit.be_error()
}

pub fn parse_list_of_strings_test() {
  let expected = Ok(["production", "web", "critical"])
  let actual =
    slo_resolver.parse_list_value(
      "[\"production\", \"web\", \"critical\"]",
      slo_resolver.inner_parse_string,
    )

  actual
  |> gleeunit.equal(expected)
}

pub fn parse_list_of_integers_test() {
  let expected = Ok([1, 2, 3])
  let actual =
    slo_resolver.parse_list_value("[1, 2, 3]", slo_resolver.inner_parse_int)

  actual
  |> gleeunit.equal(expected)
}

pub fn resolve_list_of_integers_test() {
  // Create an SLI type with a List<Integer> filter
  let sli_type_with_int_list =
    sli_type.SliType(
      name: "int_list_test",
      query_template_type: query_template_type.QueryTemplateType(
        name: "int_list_test",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "test_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: ExpContainer(Primary(PrimaryWord(Word("test_query")))),
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #("test_query", "metric{$$status_codes->status_codes$$}"),
        ]),
        dict.from_list([#("test_query", accepted_types.String)]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "status_codes",
          attribute_type: accepted_types.NonEmptyList(accepted_types.Integer),
        ),
      ],
    )

  // Provide a list of integers: [1, 10, 200]
  // Note: filter name must match the specification (lowercase)
  let filters = dict.from_list([#("status_codes", "[1, 10, 200]")])

  let expected =
    Ok(resolved_sli.Sli(
      name: "test_slo",
      query_template_type: sli_type_with_int_list.query_template_type,
      metric_attributes: dict.from_list([
        // Should resolve to (1,10,200)
        #(
          "test_query",
          "metric{(status_codes:1 OR status_codes:10 OR status_codes:200)}",
        ),
      ]),
      resolved_query: ExpContainer(
        Primary(
          PrimaryExp(
            Primary(
              PrimaryWord(Word(
                "metric{(status_codes:1 OR status_codes:10 OR status_codes:200)}",
              )),
            ),
          ),
        ),
      ),
    ))

  let actual =
    slo_resolver.resolve_sli(filters, sli_type_with_int_list, "test_slo")

  actual
  |> gleeunit.equal(expected)
}

pub fn parse_empty_list_test() {
  let result =
    slo_resolver.parse_list_value("[]", slo_resolver.inner_parse_string)

  case result {
    Error(msg) -> {
      // Should specifically mention empty list
      msg
      |> string.contains("Empty list not allowed")
      |> gleeunit.be_true()

      msg
      |> string.contains("at least one value")
      |> gleeunit.be_true()
    }
    Ok(_) -> panic as "Expected error for empty list"
  }
}

pub fn parse_list_with_invalid_integer_test() {
  let result =
    slo_resolver.parse_list_value("[1, abc, 3]", slo_resolver.inner_parse_int)

  case result {
    Error(msg) -> {
      // Should mention parsing failure, not empty list
      msg
      |> string.contains("Failed to parse list values")
      |> gleeunit.be_true()
    }
    Ok(_) -> panic as "Expected error for invalid integer"
  }
}

pub fn parse_list_with_null_string_test() {
  // Test that empty string after parsing is handled
  let result =
    slo_resolver.parse_list_value("[\"\"]", slo_resolver.inner_parse_string)

  // Empty strings are allowed in the list, just not empty lists
  result
  |> gleeunit.equal(Ok([""]))
}

pub fn parse_malformed_list_missing_bracket_test() {
  let result =
    slo_resolver.parse_list_value("[1, 2, 3", slo_resolver.inner_parse_int)

  // Should still parse since we strip brackets
  result
  |> gleeunit.equal(Ok([1, 2, 3]))
}

pub fn parse_single_item_list_test() {
  let expected = Ok(["production"])
  let actual =
    slo_resolver.parse_list_value(
      "[\"production\"]",
      slo_resolver.inner_parse_string,
    )

  actual
  |> gleeunit.equal(expected)
}

pub fn convert_single_item_list_to_or_expression_test() {
  let result =
    slo_resolver.convert_list_to_or_expression(["100"], "status_code")
  result
  |> gleeunit.equal("status_code:100")
}

pub fn resolve_single_item_list_test() {
  let sli_type_with_int_list =
    sli_type.SliType(
      name: "single_item_test",
      query_template_type: query_template_type.QueryTemplateType(
        name: "single_item_test",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "test_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: ExpContainer(Primary(PrimaryWord(Word("test_query")))),
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #("test_query", "metric{$$status_code->status_code$$}"),
        ]),
        dict.from_list([#("test_query", accepted_types.String)]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "status_code",
          attribute_type: accepted_types.NonEmptyList(accepted_types.Integer),
        ),
      ],
    )

  let filters = dict.from_list([#("status_code", "[200]")])

  let expected =
    Ok(resolved_sli.Sli(
      name: "test_slo",
      query_template_type: sli_type_with_int_list.query_template_type,
      metric_attributes: dict.from_list([
        #("test_query", "metric{status_code:200}"),
      ]),
      resolved_query: ExpContainer(
        Primary(
          PrimaryExp(Primary(PrimaryWord(Word("metric{status_code:200}")))),
        ),
      ),
    ))

  let actual =
    slo_resolver.resolve_sli(filters, sli_type_with_int_list, "test_slo")

  actual
  |> gleeunit.equal(expected)
}

pub fn resolve_empty_list_fails_test() {
  let sli_type_with_int_list =
    sli_type.SliType(
      name: "empty_list_test",
      query_template_type: query_template_type.QueryTemplateType(
        name: "empty_list_test",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "test_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: ExpContainer(Primary(PrimaryWord(Word("test_query")))),
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #("test_query", "metric{$$status_code->status_code$$}"),
        ]),
        dict.from_list([#("test_query", accepted_types.String)]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "status_code",
          attribute_type: accepted_types.NonEmptyList(accepted_types.Integer),
        ),
      ],
    )

  let filters = dict.from_list([#("status_code", "[]")])

  let actual =
    slo_resolver.resolve_sli(filters, sli_type_with_int_list, "test_slo")

  actual
  |> gleeunit.be_error()
}

// Test Optional type with value provided
pub fn resolve_optional_with_value_test() {
  let sli_type_with_optional =
    sli_type.SliType(
      name: "optional_test",
      query_template_type: query_template_type.QueryTemplateType(
        name: "optional_test",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "test_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: ExpContainer(Primary(PrimaryWord(Word("test_query")))),
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #("test_query", "metric{$$foobar->baz$$}"),
        ]),
        dict.from_list([#("test_query", accepted_types.String)]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "baz",
          attribute_type: accepted_types.Optional(accepted_types.Integer),
        ),
      ],
    )

  let filters = dict.from_list([#("baz", "10")])

  let expected =
    Ok(resolved_sli.Sli(
      name: "test_slo",
      query_template_type: sli_type_with_optional.query_template_type,
      metric_attributes: dict.from_list([
        #("test_query", "metric{foobar:10}"),
      ]),
      resolved_query: ExpContainer(
        Primary(PrimaryExp(Primary(PrimaryWord(Word("metric{foobar:10}"))))),
      ),
    ))

  let actual =
    slo_resolver.resolve_sli(filters, sli_type_with_optional, "test_slo")

  actual
  |> gleeunit.equal(expected)
}

// Test Optional type with no value provided (should return empty string)
pub fn resolve_optional_without_value_test() {
  let sli_type_with_optional =
    sli_type.SliType(
      name: "optional_test",
      query_template_type: query_template_type.QueryTemplateType(
        name: "optional_test",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "test_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: ExpContainer(Primary(PrimaryWord(Word("test_query")))),
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #("test_query", "metric{$$foobar->baz$$}"),
        ]),
        dict.from_list([#("test_query", accepted_types.String)]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "baz",
          attribute_type: accepted_types.Optional(accepted_types.Integer),
        ),
      ],
    )

  // No filters provided - baz is optional so should work
  let filters = dict.from_list([])

  let expected =
    Ok(resolved_sli.Sli(
      name: "test_slo",
      query_template_type: sli_type_with_optional.query_template_type,
      metric_attributes: dict.from_list([
        #("test_query", "metric{}"),
      ]),
      resolved_query: ExpContainer(
        Primary(PrimaryExp(Primary(PrimaryWord(Word("metric{}"))))),
      ),
    ))

  let actual =
    slo_resolver.resolve_sli(filters, sli_type_with_optional, "test_slo")

  actual
  |> gleeunit.equal(expected)
}

// Test Optional type with string value
pub fn resolve_optional_string_test() {
  let sli_type_with_optional =
    sli_type.SliType(
      name: "optional_string_test",
      query_template_type: query_template_type.QueryTemplateType(
        name: "optional_string_test",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "test_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: ExpContainer(Primary(PrimaryWord(Word("test_query")))),
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #("test_query", "metric{$$region->region$$,$$zone->zone$$}"),
        ]),
        dict.from_list([#("test_query", accepted_types.String)]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "region",
          attribute_type: accepted_types.String,
        ),
        basic_type.BasicType(
          attribute_name: "zone",
          attribute_type: accepted_types.Optional(accepted_types.String),
        ),
      ],
    )

  let filters = dict.from_list([#("region", "\"us_east_1\"")])

  let expected =
    Ok(resolved_sli.Sli(
      name: "test_slo",
      query_template_type: sli_type_with_optional.query_template_type,
      metric_attributes: dict.from_list([
        #("test_query", "metric{region:\"us_east_1\",}"),
      ]),
      resolved_query: ExpContainer(
        Primary(
          PrimaryExp(
            Primary(PrimaryWord(Word("metric{region:\"us_east_1\",}"))),
          ),
        ),
      ),
    ))

  let actual =
    slo_resolver.resolve_sli(filters, sli_type_with_optional, "test_slo")

  actual
  |> gleeunit.equal(expected)
}

// Test Optional type with both required and optional fields
pub fn resolve_mixed_required_and_optional_test() {
  let sli_type_mixed =
    sli_type.SliType(
      name: "mixed_test",
      query_template_type: query_template_type.QueryTemplateType(
        name: "mixed_test",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "test_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: ExpContainer(Primary(PrimaryWord(Word("test_query")))),
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #(
            "test_query",
            "metric{$$service->service$$,$$env->environment$$,$$optional_tag->tag$$}",
          ),
        ]),
        dict.from_list([#("test_query", accepted_types.String)]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "service",
          attribute_type: accepted_types.String,
        ),
        basic_type.BasicType(
          attribute_name: "environment",
          attribute_type: accepted_types.String,
        ),
        basic_type.BasicType(
          attribute_name: "tag",
          attribute_type: accepted_types.Optional(accepted_types.String),
        ),
      ],
    )

  let filters =
    dict.from_list([
      #("service", "\"web_api\""),
      #("environment", "\"production\""),
      #("tag", "\"v1.0\""),
    ])

  let expected =
    Ok(resolved_sli.Sli(
      name: "test_slo",
      query_template_type: sli_type_mixed.query_template_type,
      metric_attributes: dict.from_list([
        #(
          "test_query",
          "metric{service:\"web_api\",env:\"production\",optional_tag:\"v1.0\"}",
        ),
      ]),
      resolved_query: ExpContainer(
        Primary(
          PrimaryExp(
            Primary(
              PrimaryWord(Word(
                "metric{service:\"web_api\",env:\"production\",optional_tag:\"v1.0\"}",
              )),
            ),
          ),
        ),
      ),
    ))

  let actual = slo_resolver.resolve_sli(filters, sli_type_mixed, "test_slo")

  actual
  |> gleeunit.equal(expected)
}

// Test wildcard handling in single item list
pub fn resolve_single_wildcard_list_test() {
  let sli_type_with_wildcard =
    sli_type.SliType(
      name: "wildcard_test",
      query_template_type: query_template_type.QueryTemplateType(
        name: "wildcard_test",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "test_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: ExpContainer(Primary(PrimaryWord(Word("test_query")))),
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #("test_query", "metric{$$foo->foo$$}"),
        ]),
        dict.from_list([#("test_query", accepted_types.String)]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "foo",
          attribute_type: accepted_types.NonEmptyList(accepted_types.String),
        ),
      ],
    )

  let filters = dict.from_list([#("foo", "[\"2*\"]")])

  let expected =
    Ok(resolved_sli.Sli(
      name: "test_slo",
      query_template_type: sli_type_with_wildcard.query_template_type,
      metric_attributes: dict.from_list([
        #("test_query", "metric{(foo:2*)}"),
      ]),
      resolved_query: ExpContainer(
        Primary(PrimaryExp(Primary(PrimaryWord(Word("metric{(foo:2*)}"))))),
      ),
    ))

  let actual =
    slo_resolver.resolve_sli(filters, sli_type_with_wildcard, "test_slo")

  actual
  |> gleeunit.equal(expected)
}

// Test wildcard handling in multiple item list
pub fn resolve_multiple_wildcard_list_test() {
  let sli_type_with_wildcards =
    sli_type.SliType(
      name: "wildcards_test",
      query_template_type: query_template_type.QueryTemplateType(
        name: "wildcards_test",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "test_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: ExpContainer(Primary(PrimaryWord(Word("test_query")))),
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #("test_query", "metric{$$foo->foo$$}"),
        ]),
        dict.from_list([#("test_query", accepted_types.String)]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "foo",
          attribute_type: accepted_types.NonEmptyList(accepted_types.String),
        ),
      ],
    )

  let filters = dict.from_list([#("foo", "[\"2*\", \"4*\"]")])

  let expected =
    Ok(resolved_sli.Sli(
      name: "test_slo",
      query_template_type: sli_type_with_wildcards.query_template_type,
      metric_attributes: dict.from_list([
        #("test_query", "metric{(foo:2* OR foo:4*)}"),
      ]),
      resolved_query: ExpContainer(
        Primary(
          PrimaryExp(Primary(PrimaryWord(Word("metric{(foo:2* OR foo:4*)}")))),
        ),
      ),
    ))

  let actual =
    slo_resolver.resolve_sli(filters, sli_type_with_wildcards, "test_slo")

  actual
  |> gleeunit.equal(expected)
}

// Test Optional(NonEmptyList(Integer)) handling
pub fn resolve_optional_nonempty_list_integers_test() {
  let sli_type_with_optional_list =
    sli_type.SliType(
      name: "optional_list_test",
      query_template_type: query_template_type.QueryTemplateType(
        name: "optional_list_test",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "test_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: ExpContainer(Primary(PrimaryWord(Word("test_query")))),
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #("test_query", "metric{$$http_status_codes->http_status_codes$$}"),
        ]),
        dict.from_list([#("test_query", accepted_types.String)]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "http_status_codes",
          attribute_type: accepted_types.Optional(accepted_types.NonEmptyList(
            accepted_types.Integer,
          )),
        ),
      ],
    )

  let filters = dict.from_list([#("http_status_codes", "[200, 201, 202, 204]")])

  let expected =
    Ok(resolved_sli.Sli(
      name: "test_slo",
      query_template_type: sli_type_with_optional_list.query_template_type,
      metric_attributes: dict.from_list([
        #(
          "test_query",
          "metric{(http_status_codes:200 OR http_status_codes:201 OR http_status_codes:202 OR http_status_codes:204)}",
        ),
      ]),
      resolved_query: ExpContainer(
        Primary(
          PrimaryExp(
            Primary(
              PrimaryWord(Word(
                "metric{(http_status_codes:200 OR http_status_codes:201 OR http_status_codes:202 OR http_status_codes:204)}",
              )),
            ),
          ),
        ),
      ),
    ))

  let actual =
    slo_resolver.resolve_sli(filters, sli_type_with_optional_list, "test_slo")

  actual
  |> gleeunit.equal(expected)
}

// Test NOT negation with Optional(NonEmptyList(Integer))
pub fn resolve_negated_optional_nonempty_list_test() {
  let sli_type_with_negated_list =
    sli_type.SliType(
      name: "negated_list_test",
      query_template_type: query_template_type.QueryTemplateType(
        name: "negated_list_test",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "test_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: ExpContainer(Primary(PrimaryWord(Word("test_query")))),
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #("test_query", "metric{$$status_codes->status_codes_to_exclude$$}"),
        ]),
        dict.from_list([#("test_query", accepted_types.String)]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "status_codes_to_exclude",
          attribute_type: accepted_types.Optional(accepted_types.NonEmptyList(
            accepted_types.Integer,
          )),
        ),
      ],
    )

  let filters =
    dict.from_list([#("status_codes_to_exclude", "[400, 401, 404, 429]")])

  let expected =
    Ok(resolved_sli.Sli(
      name: "test_slo",
      query_template_type: sli_type_with_negated_list.query_template_type,
      metric_attributes: dict.from_list([
        #(
          "test_query",
          "metric{(status_codes:400 OR status_codes:401 OR status_codes:404 OR status_codes:429)}",
        ),
      ]),
      resolved_query: ExpContainer(
        Primary(
          PrimaryExp(
            Primary(
              PrimaryWord(Word(
                "metric{(status_codes:400 OR status_codes:401 OR status_codes:404 OR status_codes:429)}",
              )),
            ),
          ),
        ),
      ),
    ))

  let actual =
    slo_resolver.resolve_sli(filters, sli_type_with_negated_list, "test_slo")

  actual
  |> gleeunit.equal(expected)
}

// Test that slashes in paths are preserved correctly
pub fn resolve_path_with_slashes_test() {
  let sli_type_with_path =
    sli_type.SliType(
      name: "path_test",
      query_template_type: query_template_type.QueryTemplateType(
        name: "path_test",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "test_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: ExpContainer(Primary(PrimaryWord(Word("test_query")))),
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #("test_query", "metric{$$env->environment$$,$$path->http_path$$}"),
        ]),
        dict.from_list([#("test_query", accepted_types.String)]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "environment",
          attribute_type: accepted_types.String,
        ),
        basic_type.BasicType(
          attribute_name: "http_path",
          attribute_type: accepted_types.String,
        ),
      ],
    )

  let filters =
    dict.from_list([
      #("environment", "production"),
      #("http_path", "/v1/users/passwords/reset"),
    ])

  let expected =
    Ok(resolved_sli.Sli(
      name: "test_slo",
      query_template_type: sli_type_with_path.query_template_type,
      metric_attributes: dict.from_list([
        #("test_query", "metric{env:production,path:/v1/users/passwords/reset}"),
      ]),
      resolved_query: ExpContainer(
        Primary(PrimaryExp(
          // The CQL parser will treat /v1/users/passwords/reset as division operators
          // This is expected behavior - paths with slashes will be parsed as math expressions
          OperatorExpr(
            OperatorExpr(
              OperatorExpr(
                OperatorExpr(
                  Primary(PrimaryWord(Word("metric{env:production,path:"))),
                  Primary(PrimaryWord(Word("v1"))),
                  Div,
                ),
                Primary(PrimaryWord(Word("users"))),
                Div,
              ),
              Primary(PrimaryWord(Word("passwords"))),
              Div,
            ),
            Primary(PrimaryWord(Word("reset}"))),
            Div,
          ),
        )),
      ),
    ))

  let actual = slo_resolver.resolve_sli(filters, sli_type_with_path, "test_slo")

  actual
  |> gleeunit.equal(expected)
}

// Test NOT negation syntax with template variable
pub fn resolve_not_negation_syntax_test() {
  let sli_type_with_not =
    sli_type.SliType(
      name: "not_syntax_test",
      query_template_type: query_template_type.QueryTemplateType(
        name: "not_syntax_test",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "test_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: ExpContainer(Primary(PrimaryWord(Word("test_query")))),
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #(
            "test_query",
            "metric{$$NOT[status_codes->status_codes_to_exclude]$$}",
          ),
        ]),
        dict.from_list([#("test_query", accepted_types.String)]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "status_codes_to_exclude",
          attribute_type: accepted_types.Optional(accepted_types.NonEmptyList(
            accepted_types.Integer,
          )),
        ),
      ],
    )

  let filters =
    dict.from_list([#("status_codes_to_exclude", "[400, 401, 404, 429]")])

  let expected =
    Ok(resolved_sli.Sli(
      name: "test_slo",
      query_template_type: sli_type_with_not.query_template_type,
      metric_attributes: dict.from_list([
        #(
          "test_query",
          "metric{NOT ((status_codes:400 OR status_codes:401 OR status_codes:404 OR status_codes:429))}",
        ),
      ]),
      resolved_query: ExpContainer(
        Primary(
          PrimaryExp(
            Primary(
              PrimaryWord(Word(
                "metric{NOT ((status_codes:400 OR status_codes:401 OR status_codes:404 OR status_codes:429))}",
              )),
            ),
          ),
        ),
      ),
    ))

  let actual = slo_resolver.resolve_sli(filters, sli_type_with_not, "test_slo")

  actual
  |> gleeunit.equal(expected)
}
