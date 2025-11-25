import caffeine_lang_v2/parser
import deps/gleamy_spec/extensions.{describe, it}
import deps/gleamy_spec/gleeunit
import gleam/dict

pub fn parse_blueprint_specification_test() {
  describe("parse_blueprint_specification", fn() {
    describe("valid blueprints", fn() {
      it("should parse valid blueprints", fn() {
        let expected_blueprints = [
          parser.Blueprint(
            name: "success_rate_graphql",
            inputs: dict.from_list([
              #("gql_operation", parser.String),
              #("environment", parser.String),
            ]),
            queries: dict.from_list([
              #(
                "numerator",
                "sum.app.requests{operation:${gql_operation},status:success,environment:${environment}}.as_count()",
              ),
              #(
                "denominator",
                "sum.app.requests{operation:${gql_operation},environment:${environment}}.as_count()",
              ),
            ]),
            value: "numerator / denominator",
          ),
          parser.Blueprint(
            name: "latency_http",
            inputs: dict.from_list([
              #("endpoint", parser.String),
              #("status_codes", parser.NonEmptyList(parser.String)),
              #("percentile", parser.Decimal),
            ]),
            queries: dict.from_list([
              #(
                "latency_query",
                "percentile.app.latency{endpoint:${endpoint},status:${status_codes}}.at(${percentile})",
              ),
            ]),
            value: "latency_query",
          ),
        ]

        parser.parse_blueprint_specification(
          "test/caffeine_lang_v2/artifacts/blueprints.yaml",
        )
        |> gleeunit.equal(Ok(expected_blueprints))
      })
    })
  })
}
