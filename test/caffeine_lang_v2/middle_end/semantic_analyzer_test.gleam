/// Most of these tests are just integration tests so we'll focus mostly
/// just on the happy path to avoid duplicative testing.
import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/middle_end/semantic_analyzer
import caffeine_lang_v2/middle_end/vendor
import gleam/dynamic
import gleam/option
import gleeunit/should

// ==== Resolve Intermediate Representations ====
// * ✅ happy path - two IRs
pub fn resolve_intermediate_representations_test() {
  let input_irs = [
    semantic_analyzer.IntermediateRepresentation(
      "slo_one",
      "SLO",
      [
        helpers.ValueTuple("vendor", helpers.String, dynamic.string("datadog")),
        helpers.ValueTuple("env", helpers.String, dynamic.string("staging")),
        helpers.ValueTuple(
          "queries",
          helpers.Dict(helpers.String, helpers.String),
          dynamic.properties([
            #(
              dynamic.string("query_a"),
              dynamic.string("avg:memory{$$env->env$$}"),
            ),
          ]),
        ),
      ],
      option.None,
    ),
    semantic_analyzer.IntermediateRepresentation(
      "slo_two",
      "SLO",
      [
        helpers.ValueTuple("vendor", helpers.String, dynamic.string("datadog")),
        helpers.ValueTuple("region", helpers.String, dynamic.string("us-east")),
        helpers.ValueTuple(
          "queries",
          helpers.Dict(helpers.String, helpers.String),
          dynamic.properties([
            #(
              dynamic.string("query_b"),
              dynamic.string("sum:requests{$$region->region$$}"),
            ),
          ]),
        ),
      ],
      option.None,
    ),
  ]

  let expected_irs = [
    semantic_analyzer.IntermediateRepresentation(
      "slo_one",
      "SLO",
      [
        helpers.ValueTuple("vendor", helpers.String, dynamic.string("datadog")),
        helpers.ValueTuple("env", helpers.String, dynamic.string("staging")),
        helpers.ValueTuple(
          "queries",
          helpers.Dict(helpers.String, helpers.String),
          dynamic.properties([
            #(
              dynamic.string("query_a"),
              dynamic.string("avg:memory{env:staging}"),
            ),
          ]),
        ),
      ],
      option.Some(vendor.Datadog),
    ),
    semantic_analyzer.IntermediateRepresentation(
      "slo_two",
      "SLO",
      [
        helpers.ValueTuple("vendor", helpers.String, dynamic.string("datadog")),
        helpers.ValueTuple("region", helpers.String, dynamic.string("us-east")),
        helpers.ValueTuple(
          "queries",
          helpers.Dict(helpers.String, helpers.String),
          dynamic.properties([
            #(
              dynamic.string("query_b"),
              dynamic.string("sum:requests{region:us-east}"),
            ),
          ]),
        ),
      ],
      option.Some(vendor.Datadog),
    ),
  ]

  semantic_analyzer.resolve_intermediate_representations(input_irs)
  |> should.equal(Ok(expected_irs))
}

// ==== Resolve Vendor ====
// * ✅ happy path - known vendor, Datadog
pub fn resolve_vendor_test() {
  let input_ir =
    semantic_analyzer.IntermediateRepresentation(
      "foo",
      "SLO",
      [
        helpers.ValueTuple("vendor", helpers.String, dynamic.string("datadog")),
      ],
      option.None,
    )

  let expected_ir =
    semantic_analyzer.IntermediateRepresentation(
      "foo",
      "SLO",
      [
        helpers.ValueTuple("vendor", helpers.String, dynamic.string("datadog")),
      ],
      option.Some(vendor.Datadog),
    )

  semantic_analyzer.resolve_vendor(input_ir)
  |> should.equal(Ok(expected_ir))
}

// ==== Resolve Queries ====
// * ✅ happy path - multiple queries
pub fn resolve_queries_test() {
  let input_ir =
    semantic_analyzer.IntermediateRepresentation(
      "foo",
      "SLO",
      [
        helpers.ValueTuple("vendor", helpers.String, dynamic.string("datadog")),
        helpers.ValueTuple("env", helpers.String, dynamic.string("production")),
        helpers.ValueTuple("status", helpers.Boolean, dynamic.bool(True)),
        helpers.ValueTuple(
          "queries",
          helpers.Dict(helpers.String, helpers.String),
          dynamic.properties([
            #(
              dynamic.string("denominator"),
              dynamic.string("avg:system.cpu{$$env->env$$}"),
            ),
            #(
              dynamic.string("numerator"),
              dynamic.string(
                "avg:system.cpu{$$env->env$$ AND $$status->status:not$$}",
              ),
            ),
          ]),
        ),
      ],
      option.Some(vendor.Datadog),
    )

  let expected_ir =
    semantic_analyzer.IntermediateRepresentation(
      "foo",
      "SLO",
      [
        helpers.ValueTuple("vendor", helpers.String, dynamic.string("datadog")),
        helpers.ValueTuple("env", helpers.String, dynamic.string("production")),
        helpers.ValueTuple("status", helpers.Boolean, dynamic.bool(True)),
        helpers.ValueTuple(
          "queries",
          helpers.Dict(helpers.String, helpers.String),
          dynamic.properties([
            #(
              dynamic.string("denominator"),
              dynamic.string("avg:system.cpu{env:production}"),
            ),
            #(
              dynamic.string("numerator"),
              dynamic.string("avg:system.cpu{env:production AND !status:True}"),
            ),
          ]),
        ),
      ],
      option.Some(vendor.Datadog),
    )

  semantic_analyzer.resolve_queries(input_ir)
  |> should.equal(Ok(expected_ir))
}
