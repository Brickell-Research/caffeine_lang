import caffeine_lang/phase_5/terraform/datadog
import caffeine_lang/types/ast/basic_type
import caffeine_lang/types/ast/query_template_type
import caffeine_lang/types/common/accepted_types
import caffeine_lang/types/resolved/resolved_sli
import caffeine_lang/types/resolved/resolved_slo
import cql/parser.{
  Div, ExpContainer, OperatorExpr, Primary, PrimaryExp, PrimaryWord, Word,
}
import gleam/dict
import gleeunit/should

pub fn set_resource_comment_header_test() {
  let expected = "# SLO created by EzSLO for team - Type: type"
  let actual = datadog.set_resource_comment_header("team", "type")
  actual
  |> should.equal(expected)
}

pub fn resource_threshold_test() {
  let expected =
    "thresholds {\n    timeframe = \"45d\"\n    target    = 0.95\n  }"
  let actual = datadog.resource_threshold(0.95, 45)
  actual
  |> should.equal(expected)
}

pub fn resource_target_threshold_test() {
  let expected = "target = 0.95"
  let actual = datadog.resource_target_threshold(0.95)
  actual
  |> should.equal(expected)
}

pub fn resource_top_line_test() {
  let expected =
    "resource \"datadog_service_level_objective\" \"team_service_type_0\" {"
  let actual = datadog.resource_top_line("team", "service", "type", 0)
  actual
  |> should.equal(expected)
}

pub fn resource_description_test() {
  let expected = "description = \"SLO created by caffeine\""
  let actual = datadog.resource_description()
  actual
  |> should.equal(expected)
}

pub fn get_tags_test() {
  let _tags =
    dict.new()
    |> dict.insert("managed-by", "caffeine")
    |> dict.insert("team", "platform")
    |> dict.insert("environment", "production")

  let expected =
    "tags = [\"managed-by:caffeine\", \"team:platform\", \"service:production\", \"sli_type:some_slo\", \"query_type:good_over_bad\"]"
  let actual =
    datadog.get_tags("platform", "production", "some_slo", "good_over_bad")
  actual
  |> should.equal(expected)
}

pub fn tf_resource_name_test() {
  let expected =
    "resource \"datadog_service_level_objective\" team_service_type_0 {"
  let actual = datadog.tf_resource_name("team", "service", "type", 0)
  actual
  |> should.equal(expected)
}

pub fn resource_type_test() {
  let expected = "type        = \"metric\""
  let actual =
    datadog.resource_type(query_template_type.QueryTemplateType(
      specification_of_query_templates: [],
      name: "good_over_bad",
      query: ExpContainer(Primary(PrimaryWord(Word("")))),
    ))
  actual
  |> should.equal(expected)
}

pub fn slo_specification_test() {
  let expected =
    "query {\n    numerator = \"#{numerator_query}\"\n    denominator = \"#{denominator_query}\"\n  }\n"
  let actual =
    datadog.slo_specification(resolved_slo.Slo(
      window_in_days: 30,
      threshold: 99.5,
      service_name: "super_scalabale_web_service",
      team_name: "badass_platform_team",
      sli: resolved_sli.Sli(
        name: "foobar",
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
    ))
  actual
  |> should.equal(expected)
}

pub fn full_resource_body_test() {
  let expected =
    "# SLO created by EzSLO for badass_platform_team - Type: good_over_bad
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

  let actual =
    datadog.full_resource_body(
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
                attribute_name: "numerator_query",
                attribute_type: accepted_types.String,
              ),
              basic_type.BasicType(
                attribute_name: "denominator_query",
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
      ),
      0,
    )

  actual
  |> should.equal(expected)
}

pub fn slo_specification_with_list_test() {
  let expected =
    "query {\n    numerator = \"sum:requests{tags:(production OR web OR critical)}\"\n    denominator = \"sum:requests{}\"\n  }\n"
  let actual =
    datadog.slo_specification(resolved_slo.Slo(
      window_in_days: 30,
      threshold: 99.5,
      service_name: "web_service",
      team_name: "platform_team",
      sli: resolved_sli.Sli(
        name: "good_over_bad_with_list",
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
          name: "good_over_bad_with_list",
          query: ExpContainer(OperatorExpr(
            Primary(PrimaryWord(Word("numerator"))),
            Primary(PrimaryWord(Word("denominator"))),
            Div,
          )),
        ),
        metric_attributes: dict.from_list([
          #("numerator", "sum:requests{tags:(production OR web OR critical)}"),
          #("denominator", "sum:requests{}"),
        ]),
        resolved_query: ExpContainer(OperatorExpr(
          Primary(
            PrimaryExp(
              Primary(
                PrimaryWord(Word(
                  "sum:requests{tags:(production OR web OR critical)}",
                )),
              ),
            ),
          ),
          Primary(PrimaryExp(Primary(PrimaryWord(Word("sum:requests{}"))))),
          Div,
        )),
      ),
    ))
  actual
  |> should.equal(expected)
}
