import caffeine_lang/phase_4/slo_resolver
import caffeine_lang/phase_5/terraform/datadog
import caffeine_lang/types/ast/basic_type
import caffeine_lang/types/ast/organization
import caffeine_lang/types/ast/query_template_type
import caffeine_lang/types/ast/service
import caffeine_lang/types/ast/sli_type
import caffeine_lang/types/ast/slo
import caffeine_lang/types/ast/team
import caffeine_lang/types/common/accepted_types
import caffeine_lang/types/common/generic_dictionary
import cql/parser.{Div, ExpContainer, OperatorExpr, Primary, PrimaryWord, Word}
import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import gleamy_spec/should

/// End-to-end integration test using realistic organization data
/// Tests the complete flow from SLO resolution to Datadog code generation
pub fn end_to_end_organization_test() {
  // Create a realistic organization with SLOs that have CQL queries
  let availability_sli_type =
    sli_type.SliType(
      name: "availability",
      query_template_type: query_template_type.QueryTemplateType(
        name: "availability_ratio",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "success_query",
            attribute_type: accepted_types.String,
          ),
          basic_type.BasicType(
            attribute_name: "total_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: ExpContainer(OperatorExpr(
          Primary(PrimaryWord(Word("success_query"))),
          Primary(PrimaryWord(Word("total_query"))),
          Div,
        )),
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #(
            "success_query",
            "sum:http.requests{status:2xx,$$service->SERVICE$$,$$env->ENV$$}",
          ),
          #(
            "total_query",
            "sum:http.requests{$$service->SERVICE$$,$$env->ENV$$}",
          ),
        ]),
        dict.from_list([
          #("success_query", accepted_types.String),
          #("total_query", accepted_types.String),
        ]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "service",
          attribute_type: accepted_types.String,
        ),
        basic_type.BasicType(
          attribute_name: "env",
          attribute_type: accepted_types.String,
        ),
      ],
    )

  let test_slo =
    slo.Slo(
      name: "test_slo",
      typed_instatiation_of_query_templatized_variables: generic_dictionary.from_string_dict(
        dict.from_list([
          #("SERVICE", "\"web_service\""),
          #("ENV", "\"production\""),
        ]),
        dict.from_list([
          #("SERVICE", accepted_types.String),
          #("ENV", accepted_types.String),
        ]),
      )
        |> result.unwrap(generic_dictionary.new()),
      threshold: 99.9,
      sli_type: "availability",
      service_name: "web_service",
      window_in_days: 30,
    )

  let test_organization =
    organization.Organization(
      teams: [
        team.Team(name: "platform_team", slos: [test_slo]),
      ],
      service_definitions: [
        service.Service(name: "web_service", supported_sli_types: [
          availability_sli_type,
        ]),
      ],
    )

  // Step 1: Resolve SLOs from the organization
  let resolved_slos_result = slo_resolver.resolve_slos(test_organization)

  case resolved_slos_result {
    Ok(resolved_slos) -> {
      // Verify we got resolved SLOs
      list.length(resolved_slos)
      |> should.equal(1)

      let resolved_slo = case resolved_slos {
        [slo] -> slo
        _ -> panic as "Expected exactly one resolved SLO"
      }

      // Verify SLO resolution worked correctly
      resolved_slo.service_name
      |> should.equal("web_service")
      resolved_slo.team_name
      |> should.equal("platform_team")
      resolved_slo.threshold
      |> should.equal(99.9)

      // Verify metric attributes were resolved correctly
      let metric_attrs = resolved_slo.sli.metric_attributes
      dict.get(metric_attrs, "success_query")
      |> should.equal(Ok(
        "sum:http.requests{status:2xx,service:\"web_service\",env:\"production\"}",
      ))
      dict.get(metric_attrs, "total_query")
      |> should.equal(Ok(
        "sum:http.requests{service:\"web_service\",env:\"production\"}",
      ))

      // Step 2: Generate Datadog resource from resolved SLO
      let datadog_resource = datadog.full_resource_body(resolved_slo, 0)

      // Step 3: Verify the generated Datadog code makes sense
      { string.length(datadog_resource) > 0 }
      |> should.be_true()
      string.contains(datadog_resource, "web_service")
      |> should.be_true()
      string.contains(datadog_resource, "platform_team")
      |> should.be_true()
      string.contains(datadog_resource, "99.9")
      |> should.be_true()

      // Verify the resource contains resolved metric queries
      string.contains(datadog_resource, "sum:http.requests")
      |> should.be_true()
      string.contains(datadog_resource, "production")
      |> should.be_true()

      // Verify no unresolved template variables remain
      string.contains(datadog_resource, "$$")
      |> should.be_false()
    }
    Error(err) ->
      err
      |> should.equal("Should not fail")
  }
}

/// End-to-end test with Optional type - verifies optional fields work correctly
pub fn end_to_end_with_optional_test() {
  let optional_sli_type =
    sli_type.SliType(
      name: "availability_with_optional",
      query_template_type: query_template_type.QueryTemplateType(
        name: "availability_ratio",
        specification_of_query_templates: [
          basic_type.BasicType(
            attribute_name: "success_query",
            attribute_type: accepted_types.String,
          ),
          basic_type.BasicType(
            attribute_name: "total_query",
            attribute_type: accepted_types.String,
          ),
        ],
        query: ExpContainer(OperatorExpr(
          Primary(PrimaryWord(Word("success_query"))),
          Primary(PrimaryWord(Word("total_query"))),
          Div,
        )),
      ),
      typed_instatiation_of_query_templates: generic_dictionary.from_string_dict(
        dict.from_list([
          #(
            "success_query",
            "sum:http.requests{status:2xx,$$service->SERVICE$$,$$env->ENV$$,$$optional_tag->TAG$$}",
          ),
          #(
            "total_query",
            "sum:http.requests{$$service->SERVICE$$,$$env->ENV$$}",
          ),
        ]),
        dict.from_list([
          #("success_query", accepted_types.String),
          #("total_query", accepted_types.String),
        ]),
      )
        |> result.unwrap(generic_dictionary.new()),
      specification_of_query_templatized_variables: [
        basic_type.BasicType(
          attribute_name: "SERVICE",
          attribute_type: accepted_types.String,
        ),
        basic_type.BasicType(
          attribute_name: "ENV",
          attribute_type: accepted_types.String,
        ),
        basic_type.BasicType(
          attribute_name: "TAG",
          attribute_type: accepted_types.Optional(accepted_types.String),
        ),
      ],
    )

  // Test without optional tag
  let test_slo_without_tag =
    slo.Slo(
      name: "test_slo_without_tag",
      typed_instatiation_of_query_templatized_variables: generic_dictionary.from_string_dict(
        dict.from_list([
          #("SERVICE", "\"web_service\""),
          #("ENV", "\"production\""),
        ]),
        dict.from_list([
          #("SERVICE", accepted_types.String),
          #("ENV", accepted_types.String),
        ]),
      )
        |> result.unwrap(generic_dictionary.new()),
      threshold: 99.9,
      sli_type: "availability_with_optional",
      service_name: "web_service",
      window_in_days: 30,
    )

  let test_organization =
    organization.Organization(
      teams: [
        team.Team(name: "platform_team", slos: [test_slo_without_tag]),
      ],
      service_definitions: [
        service.Service(name: "web_service", supported_sli_types: [
          optional_sli_type,
        ]),
      ],
    )

  // Resolve SLOs
  let resolved_slos_result = slo_resolver.resolve_slos(test_organization)

  case resolved_slos_result {
    Ok(resolved_slos) -> {
      list.length(resolved_slos)
      |> should.equal(1)

      let resolved_slo = case resolved_slos {
        [slo] -> slo
        _ -> panic as "Expected exactly one resolved SLO"
      }

      // Verify metric attributes - optional tag should result in empty string
      let metric_attrs = resolved_slo.sli.metric_attributes
      dict.get(metric_attrs, "success_query")
      |> should.equal(Ok(
        "sum:http.requests{status:2xx,service:\"web_service\",env:\"production\",}",
      ))
      dict.get(metric_attrs, "total_query")
      |> should.equal(Ok(
        "sum:http.requests{service:\"web_service\",env:\"production\"}",
      ))

      // Generate Datadog resource
      let datadog_resource = datadog.full_resource_body(resolved_slo, 0)

      // Verify no unresolved template variables
      string.contains(datadog_resource, "$$")
      |> should.be_false()
    }
    Error(err) ->
      err
      |> should.equal("Should not fail")
  }
}
