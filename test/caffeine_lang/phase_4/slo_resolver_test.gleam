import caffeine_lang/common_types/accepted_types
import caffeine_lang/common_types/generic_dictionary
import caffeine_lang/phase_2/ast/types as ast_types
import caffeine_lang/phase_4/resolved/types as resolved_types
import caffeine_lang/phase_4/slo_resolver
import gleam/dict
import gleam/result

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

fn example_slo() -> ast_types.Slo {
  ast_types.Slo(
    typed_instatiation_of_query_templatized_variables: example_filters(),
    threshold: 99.5,
    sli_type: "good_over_bad",
    service_name: "super_scalabale_web_service",
    window_in_days: 30,
  )
}

fn example_sli_type() -> ast_types.SliType {
  ast_types.SliType(
    name: "good_over_bad",
    query_template_type: ast_types.QueryTemplateType(
      name: "good_over_bad",
      specification_of_query_templates: [
        ast_types.BasicType(
          attribute_name: "numerator_query",
          attribute_type: accepted_types.String,
        ),
        ast_types.BasicType(
          attribute_name: "denominator_query",
          attribute_type: accepted_types.String,
        ),
      ],
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
      ast_types.BasicType(
        attribute_name: "service",
        attribute_type: accepted_types.String,
      ),
      ast_types.BasicType(
        attribute_name: "environment",
        attribute_type: accepted_types.String,
      ),
      ast_types.BasicType(
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
    Ok(resolved_types.ResolvedSli(
      query_template_type: input_sli_type.query_template_type,
      metric_attributes: expected_metric_attrs,
    ))

  // Use the filters directly since resolve_sli now expects GenericDictionary
  let input_filters = example_filters()
  let actual =
    slo_resolver.resolve_sli(
      generic_dictionary.to_string_dict(input_filters),
      input_sli_type,
    )

  assert actual == expected
}

pub fn resolve_slo_test() {
  let input_sli_type = example_sli_type()

  let expected =
    Ok(resolved_types.ResolvedSlo(
      window_in_days: 30,
      threshold: 99.5,
      service_name: "super_scalabale_web_service",
      team_name: "badass_platform_team",
      sli: resolved_types.ResolvedSli(
        query_template_type: input_sli_type.query_template_type,
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
      ),
    ))

  let actual =
    slo_resolver.resolve_slo(example_slo(), "badass_platform_team", [
      input_sli_type,
    ])

  assert actual == expected
}

pub fn resolve_slos_test() {
  let input_organization =
    ast_types.Organization(
      teams: [
        ast_types.Team(name: "badass_platform_team", slos: [example_slo()]),
      ],
      service_definitions: [
        ast_types.Service(
          name: "super_scalabale_web_service",
          supported_sli_types: [
            example_sli_type(),
          ],
        ),
      ],
    )

  let expected =
    Ok([
      resolved_types.ResolvedSlo(
        window_in_days: 30,
        threshold: 99.5,
        service_name: "super_scalabale_web_service",
        team_name: "badass_platform_team",
        sli: resolved_types.ResolvedSli(
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
        ),
      ),
    ])

  let actual = slo_resolver.resolve_slos(input_organization)

  assert actual == expected
}
