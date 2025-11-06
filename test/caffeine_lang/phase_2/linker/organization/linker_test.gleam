import caffeine_lang/phase_2/linker/organization/linker
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
import gleamy_spec/extensions.{describe, it}
import gleamy_spec/gleeunit

// ==== Test Helpers ===
fn new_bt(
  name: String,
  attribute_type: accepted_types.AcceptedTypes,
) -> basic_type.BasicType {
  basic_type.BasicType(attribute_name: name, attribute_type: attribute_type)
}

pub fn linker_test() {
  describe("linker", fn() {
    it("should return all yaml files from test artifacts directory", fn() {
      let actual =
        linker.get_instantiation_yaml_files("./test/caffeine_lang/artifacts")

      let expected_files = [
        "./test/caffeine_lang/artifacts/platform/less_reliable_service.yaml",
        "./test/caffeine_lang/artifacts/platform/reliable_service.yaml",
        "./test/caffeine_lang/artifacts/platform/reliable_service_invalid_sli_type_type.yaml",
        "./test/caffeine_lang/artifacts/platform/reliable_service_invalid_threshold_type.yaml",
        "./test/caffeine_lang/artifacts/platform/reliable_service_missing_name.yaml",
        "./test/caffeine_lang/artifacts/platform/reliable_service_missing_typed_instatiation_of_query_templatized_variables.yaml",
        "./test/caffeine_lang/artifacts/platform/reliable_service_missing_sli_type.yaml",
        "./test/caffeine_lang/artifacts/platform/reliable_service_missing_slos.yaml",
        "./test/caffeine_lang/artifacts/platform/reliable_service_missing_threshold.yaml",
        "./test/caffeine_lang/artifacts/platform/simple_yaml_load_test.yaml",
      ]

      case actual {
        Ok(files) -> {
          list.sort(files, string.compare)
          |> gleeunit.equal(list.sort(expected_files, string.compare))
        }
        Error(_) -> panic as "Failed to read instantiation files"
      }
    })

    it("should successfully link specification and instantiation files", fn() {
      let actual =
        linker.link_specification_and_instantiation(
          "./test/caffeine_lang/artifacts/some_organization/specifications",
          "./test/caffeine_lang/artifacts/some_organization",
        )

      let expected_slo_reliable_service =
        slo.Slo(
          name: "createappointment_production",
          threshold: 99.9,
          sli_type: "success_rate",
          service_name: "reliable_service",
          typed_instatiation_of_query_templatized_variables: generic_dictionary.GenericDictionary(
            dict.from_list([
              #(
                "environment",
                generic_dictionary.TypedValue(
                  "production",
                  accepted_types.Optional(accepted_types.String),
                ),
              ),
              #(
                "graphql_operation_name",
                generic_dictionary.TypedValue(
                  "createappointment",
                  accepted_types.Optional(accepted_types.String),
                ),
              ),
            ]),
          ),
          window_in_days: 7,
        )

      let expected_basic_type_1 =
        new_bt("environment", accepted_types.Optional(accepted_types.String))

      let expected_basic_type_2 =
        new_bt(
          "graphql_operation_name",
          accepted_types.Optional(accepted_types.String),
        )

      let expected_query_template_type =
        query_template_type.QueryTemplateType(
          name: "valid_over_total",
          specification_of_query_templates: [
            expected_basic_type_2,
            expected_basic_type_1,
          ],
          query: ExpContainer(OperatorExpr(
            Primary(PrimaryWord(Word("numerator"))),
            Primary(PrimaryWord(Word("denominator"))),
            Div,
          )),
        )

      let expected_typed_instatiation =
        generic_dictionary.from_string_dict(
          dict.from_list([
            #(
              "numerator",
              "sum.graphql.hits_and_errors{$$env->environment$$, $$graphql.operation_name->graphql_operation_name$$, $$team->team$$, status:info}.as_count()",
            ),
            #(
              "denominator",
              "sum.graphql.hits_and_errors{$$env->environment$$, $$graphql.operation_name->graphql_operation_name$$, $$team->team$$}.as_count()",
            ),
          ]),
          dict.from_list([
            #("numerator", accepted_types.String),
            #("denominator", accepted_types.String),
          ]),
        )
        |> result.unwrap(generic_dictionary.new())

      let expected_sli_type =
        sli_type.SliType(
          name: "success_rate",
          query_template_type: expected_query_template_type,
          typed_instatiation_of_query_templates: expected_typed_instatiation,
          specification_of_query_templatized_variables: [
            expected_basic_type_2,
            expected_basic_type_1,
            new_bt("team", accepted_types.Optional(accepted_types.String)),
          ],
        )

      let expected =
        Ok(
          organization.Organization(
            service_definitions: [
              service.Service(name: "reliable_service", supported_sli_types: [
                expected_sli_type,
              ]),
            ],
            teams: [
              team.Team(name: "platform", slos: [
                expected_slo_reliable_service,
              ]),
            ],
          ),
        )

      actual
      |> gleeunit.equal(expected)
    })
  })
}
