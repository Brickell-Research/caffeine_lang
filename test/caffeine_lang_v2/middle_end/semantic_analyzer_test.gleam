import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/middle_end/semantic_analyzer
import caffeine_lang_v2/middle_end/vendor
import gleam/dynamic
import gleeunit/should

/// Most of these tests are just integration tests so we'll focus mostly
/// just on the happy path to avoid duplicative testing.
// ==== Resolve Vendor ====
// * ✅ happy path - known vendor, Datadog
pub fn resolve_vendor_test() {
  let ir =
    semantic_analyzer.IntermediateRepresentation("foo", "SLO", [
      helpers.ValueTuple("vendor", helpers.String, dynamic.string("datadog")),
    ])

  semantic_analyzer.resolve_vendor(ir)
  |> should.equal(Ok(vendor.Datadog))
}

// ==== Resolve Queries ====
// * ✅ happy path - multiple queries
pub fn resolve_queries_test() {
  let input_ir =
    semantic_analyzer.IntermediateRepresentation("foo", "SLO", [
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
    ])

  let expected_ir =
    semantic_analyzer.IntermediateRepresentation("foo", "SLO", [
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
    ])

  semantic_analyzer.resolve_queries(input_ir, vendor.Datadog)
  |> should.equal(Ok(expected_ir))
}
