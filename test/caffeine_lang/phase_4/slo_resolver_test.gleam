import caffeine_lang/cql/parser.{
  Add, Div, ExpContainer, Mul, OperatorExpr, Primary, PrimaryExp, PrimaryWord,
  Sub, Word,
}
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
import gleam/dict
import gleam/result
import gleeunit/should

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
          "max:latency(<100ms, {service=$$SERVICE$$,requests_valid=$$REQUESTS_VALID$$,environment=$$ENVIRONMENT$$})",
        ),
        #(
          "denominator_query",
          "max:latency(<100ms, {service=$$SERVICE$$,requests_valid=$$REQUESTS_VALID$$,environment=$$ENVIRONMENT$$})",
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
        "max:latency(<100ms, {service=\"super_scalabale_web_service\",requests_valid=true,environment=production})",
      ),
      #(
        "denominator_query",
        "max:latency(<100ms, {service=\"super_scalabale_web_service\",requests_valid=true,environment=production})",
      ),
    ])

  let expected =
    Ok(resolved_sli.Sli(
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
    )

  actual
  |> should.equal(expected)
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
        query_template_type: expected_query_template_type,
        metric_attributes: dict.from_list([
          #(
            "numerator_query",
            "max:latency(<100ms, {service=\"super_scalabale_web_service\",requests_valid=true,environment=production})",
          ),
          #(
            "denominator_query",
            "max:latency(<100ms, {service=\"super_scalabale_web_service\",requests_valid=true,environment=production})",
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
  |> should.equal(expected)
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
          query_template_type: example_sli_type().query_template_type,
          metric_attributes: dict.from_list([
            #(
              "numerator_query",
              "max:latency(<100ms, {service=\"super_scalabale_web_service\",requests_valid=true,environment=production})",
            ),
            #(
              "denominator_query",
              "max:latency(<100ms, {service=\"super_scalabale_web_service\",requests_valid=true,environment=production})",
            ),
          ]),
          resolved_query: ExpContainer(Primary(PrimaryWord(Word("")))),
        ),
      ),
    ])

  let actual = slo_resolver.resolve_slos(input_organization)

  actual
  |> should.equal(expected)
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
          #("numerator_query", "sum:requests.success{service=$$SERVICE$$}"),
          #("denominator_query", "sum:requests.total{service=$$SERVICE$$}"),
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
            PrimaryWord(Word("sum:requests.success{service=\"web_api\"}")),
          ),
        ),
      ),
      Primary(
        PrimaryExp(
          Primary(
            PrimaryWord(Word("sum:requests.total{service=\"web_api\"}")),
          ),
        ),
      ),
      Div,
    ))

  let expected =
    Ok(resolved_sli.Sli(
      query_template_type: sli_type_with_query.query_template_type,
      metric_attributes: dict.from_list([
        #("numerator_query", "sum:requests.success{service=\"web_api\"}"),
        #("denominator_query", "sum:requests.total{service=\"web_api\"}"),
      ]),
      resolved_query: expected_resolved_query,
    ))

  let actual = slo_resolver.resolve_sli(filters, sli_type_with_query)
  
  actual
  |> should.equal(expected)
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
      name: "nested_expression",
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
          #("a_query", "metric_a{env=$$ENV$$}"),
          #("b_query", "metric_b{env=$$ENV$$}"),
          #("c_query", "metric_c{env=$$ENV$$}"),
          #("d_query", "metric_d{env=$$ENV$$}"),
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
        Primary(PrimaryExp(Primary(PrimaryWord(Word("metric_a{env=prod}"))))),
        Primary(PrimaryExp(Primary(PrimaryWord(Word("metric_b{env=prod}"))))),
        Add,
      ),
      OperatorExpr(
        Primary(PrimaryExp(Primary(PrimaryWord(Word("metric_c{env=prod}"))))),
        Primary(PrimaryExp(Primary(PrimaryWord(Word("metric_d{env=prod}"))))),
        Mul,
      ),
      Sub,
    ))

  let expected =
    Ok(resolved_sli.Sli(
      query_template_type: sli_type_nested.query_template_type,
      metric_attributes: dict.from_list([
        #("a_query", "metric_a{env=prod}"),
        #("b_query", "metric_b{env=prod}"),
        #("c_query", "metric_c{env=prod}"),
        #("d_query", "metric_d{env=prod}"),
      ]),
      resolved_query: expected_resolved_query,
    ))

  let actual = slo_resolver.resolve_sli(filters, sli_type_nested)
  
  actual
  |> should.equal(expected)
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
          #("test_query", "metric{service=$$SERVICE$$,region=$$REGION$$}"),
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

  // Only provide SERVICE, missing REGION
  let incomplete_filters = dict.from_list([#("SERVICE", "\"api_service\"")])

  let expected =
    Ok(resolved_sli.Sli(
      query_template_type: sli_type_with_missing_vars.query_template_type,
      metric_attributes: dict.from_list([
        // REGION should remain as $$REGION$$ since it's not provided
        #("test_query", "metric{service=\"api_service\",region=$$REGION$$}"),
      ]),
      resolved_query: ExpContainer(
        Primary(
          PrimaryExp(
            Primary(
              PrimaryWord(Word(
                "metric{service=\"api_service\",region=$$REGION$$}",
              )),
            ),
          ),
        ),
      ),
    ))

  let actual =
    slo_resolver.resolve_sli(incomplete_filters, sli_type_with_missing_vars)
  
  actual
  |> should.equal(expected)
}

pub fn parse_list_of_strings_test() {
  let expected = Ok(["production", "web", "critical"])
  let actual =
    slo_resolver.parse_list_value(
      "[\"production\", \"web\", \"critical\"]",
      slo_resolver.inner_parse_string,
    )
  
  actual
  |> should.equal(expected)
}

pub fn parse_list_of_integers_test() {
  let expected = Ok([1, 2, 3])
  let actual =
    slo_resolver.parse_list_value("[1, 2, 3]", slo_resolver.inner_parse_int)
  
  actual
  |> should.equal(expected)
}
