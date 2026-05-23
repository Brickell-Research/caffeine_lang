import caffeine_lang/analysis/vendor
import caffeine_lang/codegen/relay
import caffeine_lang/identifiers
import caffeine_lang/linker/ir
import caffeine_lang/types
import caffeine_lang/value
import gleam/dict
import gleam/option
import gleeunit/should

// ==== Helpers ====

/// Build a minimal Resolved IR with a single external-signal indicator. The
/// `unique_id` controls the synthesized metric name. Pass `option.None` for
/// `value_extraction` to get a count-style entry; pass `option.Some(...)` for
/// a distribution-style entry.
fn make_external_ir(
  unique_id: String,
  indicator_name: String,
  source: String,
  match: dict.Dict(String, value.Value),
  value_extraction: option.Option(ir.ExternalValueExtraction),
) -> ir.IntermediateRepresentation(ir.Resolved) {
  let indicators =
    dict.from_list([
      #(
        indicator_name,
        ir.ExternalSignal(
          source: source,
          match: match,
          value_extraction: value_extraction,
        ),
      ),
    ])
  make_ir(unique_id, indicators)
}

/// Same shape as `make_external_ir` but seeded with a literal-query
/// indicator, so the relay codegen should skip the IR entirely.
fn make_literal_ir(
  unique_id: String,
  indicator_name: String,
  query: String,
) -> ir.IntermediateRepresentation(ir.Resolved) {
  let indicators =
    dict.from_list([#(indicator_name, ir.LiteralQuery(query))])
  make_ir(unique_id, indicators)
}

fn make_ir(
  unique_id: String,
  indicators: dict.Dict(String, ir.IndicatorSource),
) -> ir.IntermediateRepresentation(ir.Resolved) {
  ir.IntermediateRepresentation(
    metadata: ir.IntermediateRepresentationMetaData(
      friendly_label: identifiers.ExpectationLabel("expectation"),
      org_name: identifiers.OrgName("test"),
      service_name: identifiers.ServiceName("service"),
      measurement_name: identifiers.MeasurementName("test_measurement"),
      team_name: identifiers.TeamName("team"),
      misc: dict.new(),
    ),
    unique_identifier: unique_id,
    values: [],
    slo: ir.SloFields(
      threshold: 99.0,
      indicators: indicators,
      window_in_days: 30,
      evaluation: option.None,
      tags: [],
      runbook: option.None,
      depends_on: option.None,
      description: option.None,
      below_ms: option.None,
      expectation_type: option.None,
    ),
    vendor: option.Some(vendor.Datadog),
  )
}

// ==== generate ====

// * ✅ empty IR list → None (nothing to route)
pub fn generate_empty_test() {
  relay.generate([]) |> should.equal(option.None)
}

// * ✅ IRs with only literal queries → None (relay has nothing to route)
pub fn generate_only_literal_queries_test() {
  relay.generate([make_literal_ir("acme_payments_checkout", "n", "sum:foo")])
  |> should.equal(option.None)
}

// * ✅ one count-style external signal → valid JSON with metric + count kind
pub fn generate_single_count_test() {
  let match =
    dict.from_list([
      #("name", value.StringValue("outcome")),
      #("value", value.StringValue("pass")),
    ])
  let irs = [
    make_external_ir(
      "acme_payments_checkout",
      "good",
      "langfuse",
      match,
      option.None,
    ),
  ]
  let assert option.Some(json_text) = relay.generate(irs)

  // Schema-shape assertions. The JSON encoder's key order isn't guaranteed,
  // so we use substring presence rather than byte-exact equality.
  json_text
  |> should.equal(
    "{\"version\":1,\"signals\":[{\"metric\":\"caffeine.acme_payments_checkout.good\",\"kind\":\"count\",\"source\":\"langfuse\",\"match\":{\"name\":\"outcome\",\"value\":\"pass\"},\"value_path\":null}]}",
  )
}

// * ✅ distribution-style external signal (with value_extraction) → kind distribution
pub fn generate_single_distribution_test() {
  let match = dict.from_list([#("name", value.StringValue("faithfulness"))])
  let value_extraction =
    option.Some(ir.ExternalValueExtraction(
      path: "value",
      type_: types.PrimitiveType(types.NumericType(types.Float)),
    ))
  let irs = [
    make_external_ir(
      "acme_payments_checkout",
      "score",
      "langfuse",
      match,
      value_extraction,
    ),
  ]
  let assert option.Some(json_text) = relay.generate(irs)
  json_text
  |> should.equal(
    "{\"version\":1,\"signals\":[{\"metric\":\"caffeine.acme_payments_checkout.score\",\"kind\":\"distribution\",\"source\":\"langfuse\",\"match\":{\"name\":\"faithfulness\"},\"value_path\":\"value\"}]}",
  )
}

// * ✅ mixed: literal-query indicators ignored, external indicators emitted
pub fn generate_mixed_indicators_test() {
  let match = dict.from_list([#("name", value.StringValue("outcome"))])
  let mixed_indicators =
    dict.from_list([
      #("good", ir.ExternalSignal(
        source: "langfuse",
        match: match,
        value_extraction: option.None,
      )),
      #("legacy", ir.LiteralQuery("sum:legacy.metric.as_count()")),
    ])
  let assert option.Some(json_text) =
    relay.generate([make_ir("acme_payments_checkout", mixed_indicators)])

  json_text
  |> should.equal(
    "{\"version\":1,\"signals\":[{\"metric\":\"caffeine.acme_payments_checkout.good\",\"kind\":\"count\",\"source\":\"langfuse\",\"match\":{\"name\":\"outcome\"},\"value_path\":null}]}",
  )
}

// * ✅ multiple IRs each contribute their entries
pub fn generate_multiple_irs_test() {
  let make = fn(unique_id, name) {
    make_external_ir(
      unique_id,
      name,
      "langfuse",
      dict.from_list([#("name", value.StringValue(name))]),
      option.None,
    )
  }
  let assert option.Some(json_text) =
    relay.generate([
      make("acme_payments_faithfulness", "score"),
      make("acme_payments_groundedness", "score"),
    ])

  json_text
  |> should.equal(
    "{\"version\":1,\"signals\":["
      <> "{\"metric\":\"caffeine.acme_payments_faithfulness.score\",\"kind\":\"count\",\"source\":\"langfuse\",\"match\":{\"name\":\"score\"},\"value_path\":null},"
      <> "{\"metric\":\"caffeine.acme_payments_groundedness.score\",\"kind\":\"count\",\"source\":\"langfuse\",\"match\":{\"name\":\"score\"},\"value_path\":null}"
      <> "]}",
  )
}
