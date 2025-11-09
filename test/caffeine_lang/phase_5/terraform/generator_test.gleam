import caffeine_lang/phase_2/linker/basic_type
import caffeine_lang/phase_2/linker/query_template_type
import caffeine_lang/phase_4/resolved_sli
import caffeine_lang/phase_4/resolved_slo
import caffeine_lang/phase_5/terraform/generator
import caffeine_lang/types/accepted_types
import caffeine_query_language/parser
import deps/gleamy_spec/extensions.{describe, it}
import deps/gleamy_spec/gleeunit
import gleam/dict

pub fn generator_test() {
  describe("generator", fn() {
    it("should build provider for datadog", fn() {
      let expected = {
        "terraform {
required_providers {
    datadog = {
      source  = \"DataDog/datadog\"
      version = \"~> 3.0\"
    }
  }
}

provider \"datadog\" {
  api_key = var.DATADOG_API_KEY
  app_key = var.DATADOG_APP_KEY
}"
      }

      let actual = generator.build_provider([generator.Datadog])

      actual
      |> gleeunit.equal(expected)
    })

    it("should build variables for datadog", fn() {
      let expected = {
        "variable \"DATADOG_API_KEY\" {
  type        = string
  description = \"Datadog API key\"
  sensitive   = true
  default     = null
}

variable \"DATADOG_APP_KEY\" {
  type        = string
  description = \"Datadog Application key\"
  sensitive   = true
  default     = null
}"
      }

      let actual = generator.build_variables([generator.Datadog])

      actual
      |> gleeunit.equal(expected)
    })

    it("should build backend", fn() {
      let expected = {
        "terraform {
  backend \"local\" {
    path = \"terraform.tfstate\"
  }
}"
      }

      let actual = generator.build_backend()

      actual
      |> gleeunit.equal(expected)
    })

    it("should build main with empty slos", fn() {
      let expected = {
        "terraform {
  backend \"local\" {
    path = \"terraform.tfstate\"
  }
}

"
      }

      let actual = generator.build_main([])

      actual
      |> gleeunit.equal(expected)
    })

    it("should build main with one slo", fn() {
      let expected =
        "terraform {
  backend \"local\" {
    path = \"terraform.tfstate\"
  }
}

# SLO created by EzSLO for badass_platform_team - Type: good_over_bad
resource \"datadog_service_level_objective\" \"badass_platform_team_super_scalabale_web_service_good_over_bad_0\" {
  name = \"badass_platform_team_super_scalabale_web_service_some_slo\"
  type        = \"metric\"
  description = \"SLO created by caffeine\"
  
  query {
    numerator = \"#{numerator_query}\"
    denominator = \"#{denominator_query}\"
  }

  thresholds {
    timeframe = \"30d\"
    target    = 99.5
  }

  tags = [\"managed-by:caffeine\", \"team:badass_platform_team\", \"service:super_scalabale_web_service\", \"sli_type:some_slo\", \"query_type:good_over_bad\"]
}"

      let resolved_slo =
        resolved_slo.Slo(
          window_in_days: 30,
          threshold: 99.5,
          service_name: "super_scalabale_web_service",
          team_name: "badass_platform_team",
          sli: resolved_sli.Sli(
            name: "some_slo",
            query_template_type: query_template_type.QueryTemplateType(
              specification_of_query_templates: [
                basic_type.BasicType(
                  attribute_name: "numerator",
                  attribute_type: accepted_types.String,
                ),
                basic_type.BasicType(
                  attribute_name: "denominator",
                  attribute_type: accepted_types.String,
                ),
              ],
              name: "good_over_bad",
              query: parser.ExpContainer(parser.OperatorExpr(
                parser.Primary(
                  parser.PrimaryWord(parser.Word("#{numerator_query}")),
                ),
                parser.Primary(
                  parser.PrimaryWord(parser.Word("#{denominator_query}")),
                ),
                parser.Div,
              )),
            ),
            metric_attributes: dict.from_list([
              #("numerator", "#{numerator_query}"),
              #("denominator", "#{denominator_query}"),
            ]),
            resolved_query: parser.ExpContainer(parser.OperatorExpr(
              parser.Primary(
                parser.PrimaryWord(parser.Word("#{numerator_query}")),
              ),
              parser.Primary(
                parser.PrimaryWord(parser.Word("#{denominator_query}")),
              ),
              parser.Div,
            )),
          ),
        )

      let actual = generator.build_main([resolved_slo])

      actual
      |> gleeunit.equal(expected)
    })
  })
}
