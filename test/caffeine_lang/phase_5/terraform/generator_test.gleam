import caffeine_lang/cql/parser.{
  Div, ExpContainer, OperatorExpr, Primary, PrimaryWord, Word,
}
import caffeine_lang/phase_5/terraform/generator
import caffeine_lang/types/ast/basic_type
import caffeine_lang/types/ast/query_template_type
import caffeine_lang/types/common/accepted_types
import caffeine_lang/types/resolved/resolved_sli
import caffeine_lang/types/resolved/resolved_slo
import gleam/dict
import gleeunit/should

pub fn build_provider_datadog_test() {
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
  |> should.equal(expected)
}

pub fn build_variables_datadog_test() {
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
  |> should.equal(expected)
}

pub fn build_backend_test() {
  let expected = {
    "terraform {
  backend \"local\" {
    path = \"terraform.tfstate\"
  }
}"
  }

  let actual = generator.build_backend()

  actual
  |> should.equal(expected)
}

pub fn build_main_empty_test() {
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
  |> should.equal(expected)
}

pub fn build_main_one_slo_test() {
  let expected =
    "terraform {
  backend \"local\" {
    path = \"terraform.tfstate\"
  }
}

# SLO created by EzSLO for badass_platform_team - Type: good_over_bad
resource \"datadog_service_level_objective\" \"badass_platform_team_super_scalabale_web_service_good_over_bad_0\" {
  name = \"badass_platform_team_super_scalabale_web_service_good_over_bad_0\"
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

  tags = [\"managed-by:caffeine\", \"team:badass_platform_team\", \"service:super_scalabale_web_service\", \"sli:good_over_bad\"]
}"

  let resolved_slo =
    resolved_slo.Slo(
      window_in_days: 30,
      threshold: 99.5,
      service_name: "super_scalabale_web_service",
      team_name: "badass_platform_team",
      sli: resolved_sli.Sli(
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
          query: ExpContainer(OperatorExpr(
            Primary(PrimaryWord(Word("#{numerator_query}"))),
            Primary(PrimaryWord(Word("#{denominator_query}"))),
            Div,
          )),
        ),
        metric_attributes: dict.from_list([
          #("numerator", "#{numerator_query}"),
          #("denominator", "#{denominator_query}"),
        ]),
        resolved_query: ExpContainer(OperatorExpr(
          Primary(PrimaryWord(Word("#{numerator_query}"))),
          Primary(PrimaryWord(Word("#{denominator_query}"))),
          Div,
        )),
      ),
    )

  let actual = generator.build_main([resolved_slo])

  actual
  |> should.equal(expected)
}
