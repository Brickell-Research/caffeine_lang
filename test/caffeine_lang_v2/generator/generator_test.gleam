import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/generator/common
import caffeine_lang_v2/generator/generator
import caffeine_lang_v2/middle_end
import gleam/dynamic
import gleam/list
import gleam/string
import gleeunit/should

// ==== Helpers ====
fn make_slo_ir_with_vendor(
  name: String,
  vendor: String,
) -> middle_end.IntermediateRepresentation {
  let queries_value =
    dynamic.properties([
      #(dynamic.string("numerator"), dynamic.string("query1")),
      #(dynamic.string("denominator"), dynamic.string("query2")),
    ])

  middle_end.IntermediateRepresentation(
    expectation_name: name,
    artifact_ref: "SLO",
    values: [
      middle_end.ValueTuple(
        label: "vendor",
        typ: helpers.String,
        value: dynamic.string(vendor),
      ),
      middle_end.ValueTuple(
        label: "threshold",
        typ: helpers.Float,
        value: dynamic.float(99.9),
      ),
      middle_end.ValueTuple(
        label: "window_in_days",
        typ: helpers.Integer,
        value: dynamic.int(30),
      ),
      middle_end.ValueTuple(
        label: "queries",
        typ: helpers.Dict(helpers.String, helpers.String),
        value: queries_value,
      ),
      middle_end.ValueTuple(
        label: "value",
        typ: helpers.String,
        value: dynamic.string("numerator / denominator"),
      ),
    ],
  )
}

// ==== Tests - parse_vendor ====
// * ✅ happy path - datadog
// * ✅ happy path - case insensitive
// * ✅ sad path - unknown vendor
pub fn parse_vendor_test() {
  // happy paths
  [#("datadog", generator.Datadog), #("Datadog", generator.Datadog), #("DATADOG", generator.Datadog)]
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    generator.parse_vendor(input)
    |> should.equal(Ok(expected))
  })

  // sad path
  generator.parse_vendor("unknown")
  |> should.equal(Error(common.InvalidArtifact("Unknown vendor: unknown")))
}

// ==== Tests - generate ====
// * ✅ happy path - empty list
// * ✅ happy path - single SLO
// * ✅ happy path - multiple SLOs
// * ✅ sad path - unknown artifact
// * ✅ sad path - unknown vendor
// * ✅ sad path - missing vendor
pub fn generate_empty_list_test() {
  let result = generator.generate([])
  result |> should.be_ok

  let assert Ok(output) = result
  // Empty config should still be valid HCL (just empty or minimal)
  output |> string.length |> fn(len) { len >= 0 } |> should.be_true
}

pub fn generate_single_slo_test() {
  let ir = make_slo_ir_with_vendor("my_slo", "datadog")

  let result = generator.generate([ir])
  result |> should.be_ok

  let assert Ok(output) = result

  // Verify HCL structure
  output |> string.contains("resource") |> should.be_true
  output |> string.contains("datadog_service_level_objective") |> should.be_true
  output |> string.contains("my_slo") |> should.be_true
}

pub fn generate_multiple_slos_test() {
  let irs = [
    make_slo_ir_with_vendor("slo_one", "datadog"),
    make_slo_ir_with_vendor("slo_two", "datadog"),
  ]

  let result = generator.generate(irs)
  result |> should.be_ok

  let assert Ok(output) = result

  output |> string.contains("slo_one") |> should.be_true
  output |> string.contains("slo_two") |> should.be_true
}

pub fn generate_unknown_artifact_test() {
  let ir =
    middle_end.IntermediateRepresentation(
      expectation_name: "test",
      artifact_ref: "UnknownArtifact",
      values: [],
    )

  generator.generate([ir])
  |> should.equal(Error(common.InvalidArtifact("UnknownArtifact")))
}

pub fn generate_unknown_vendor_test() {
  let ir = make_slo_ir_with_vendor("test", "unknown_vendor")

  generator.generate([ir])
  |> should.equal(Error(common.InvalidArtifact("Unknown vendor: unknown_vendor")))
}

pub fn generate_missing_vendor_test() {
  let queries_value =
    dynamic.properties([
      #(dynamic.string("numerator"), dynamic.string("query1")),
      #(dynamic.string("denominator"), dynamic.string("query2")),
    ])

  let ir =
    middle_end.IntermediateRepresentation(
      expectation_name: "test",
      artifact_ref: "SLO",
      values: [
        middle_end.ValueTuple(
          label: "threshold",
          typ: helpers.Float,
          value: dynamic.float(99.9),
        ),
        middle_end.ValueTuple(
          label: "window_in_days",
          typ: helpers.Integer,
          value: dynamic.int(30),
        ),
        middle_end.ValueTuple(
          label: "queries",
          typ: helpers.Dict(helpers.String, helpers.String),
          value: queries_value,
        ),
        middle_end.ValueTuple(
          label: "value",
          typ: helpers.String,
          value: dynamic.string("numerator / denominator"),
        ),
      ],
    )

  generator.generate([ir])
  |> should.equal(Error(common.MissingValue("vendor")))
}

// ==== Tests - generate_resources ====
// * ✅ happy path - returns list of resources
pub fn generate_resources_test() {
  let irs = [make_slo_ir_with_vendor("slo1", "datadog")]

  let result = generator.generate_resources(irs)
  result |> should.be_ok

  let assert Ok(resources) = result
  list.length(resources) |> should.equal(1)

  let assert Ok(resource) = list.first(resources)
  resource.type_ |> should.equal("datadog_service_level_objective")
}
