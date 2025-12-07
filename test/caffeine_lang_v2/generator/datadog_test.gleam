import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/generator/common
import caffeine_lang_v2/generator/datadog
import caffeine_lang_v2/middle_end
import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/string
import gleeunit/should
import terra_madre/hcl
import terra_madre/render

// ==== Helpers ====
// Note: The generator expects pre-resolved queries from the middle-end.
// These helpers create IRs with already-resolved numerator_query/denominator_query.
fn make_slo_ir(
  name: String,
  threshold: Float,
  window_in_days: Int,
  numerator_query: String,
  denominator_query: String,
) -> middle_end.IntermediateRepresentation {
  middle_end.IntermediateRepresentation(
    expectation_name: name,
    artifact_ref: "SLO",
    values: [
      middle_end.ValueTuple(
        label: "threshold",
        typ: helpers.Float,
        value: dynamic.float(threshold),
      ),
      middle_end.ValueTuple(
        label: "window_in_days",
        typ: helpers.Integer,
        value: dynamic.int(window_in_days),
      ),
      middle_end.ValueTuple(
        label: "numerator_query",
        typ: helpers.String,
        value: dynamic.string(numerator_query),
      ),
      middle_end.ValueTuple(
        label: "denominator_query",
        typ: helpers.String,
        value: dynamic.string(denominator_query),
      ),
    ],
  )
}

fn make_incomplete_ir(
  missing: String,
) -> middle_end.IntermediateRepresentation {
  let base_values = [
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
      label: "numerator_query",
      typ: helpers.String,
      value: dynamic.string("sum:requests.success{service:api}"),
    ),
    middle_end.ValueTuple(
      label: "denominator_query",
      typ: helpers.String,
      value: dynamic.string("sum:requests.total{service:api}"),
    ),
  ]

  let filtered_values =
    base_values
    |> list.filter(fn(vt) { vt.label != missing })

  middle_end.IntermediateRepresentation(
    expectation_name: "test",
    artifact_ref: "SLO",
    values: filtered_values,
  )
}

// ==== Tests - generate_slo ====
// * ✅ happy path - generates valid SLO resource
// * ✅ happy path - resource name is sanitized
// * ✅ happy path - timeframe is correct for different windows
// * ✅ sad path - missing threshold
// * ✅ sad path - missing window_in_days
// * ✅ sad path - missing numerator_query
// * ✅ sad path - missing denominator_query
pub fn generate_slo_happy_path_test() {
  let ir =
    make_slo_ir(
      "my_service_availability",
      99.9,
      30,
      "sum:requests.success{service:api}",
      "sum:requests.total{service:api}",
    )

  let result = datadog.generate_slo(ir)
  result |> should.be_ok

  let assert Ok(resource) = result

  // Check resource type and name
  resource.type_ |> should.equal("datadog_service_level_objective")
  resource.name |> should.equal("my_service_availability")

  // Check attributes
  let assert Ok(name_attr) = dict.get(resource.attributes, "name")
  name_attr |> should.equal(hcl.StringLiteral("my_service_availability"))

  let assert Ok(type_attr) = dict.get(resource.attributes, "type")
  type_attr |> should.equal(hcl.StringLiteral("metric"))

  // Check that blocks exist (query and thresholds)
  list.length(resource.blocks) |> should.equal(2)
}

pub fn generate_slo_sanitized_name_test() {
  let ir =
    make_slo_ir(
      "My Service With Spaces",
      99.9,
      30,
      "query1",
      "query2",
    )

  let result = datadog.generate_slo(ir)
  result |> should.be_ok

  let assert Ok(resource) = result
  resource.name |> should.equal("my_service_with_spaces")
}

pub fn generate_slo_timeframes_test() {
  [#(7, "7d"), #(30, "30d"), #(90, "90d")]
  |> list.each(fn(pair) {
    let #(days, expected_timeframe) = pair
    let ir = make_slo_ir("test", 99.9, days, "query1", "query2")

    let result = datadog.generate_slo(ir)
    result |> should.be_ok

    let assert Ok(resource) = result

    // Find the thresholds block and check timeframe
    let assert Ok(thresholds_block) =
      resource.blocks
      |> list.find(fn(b) { b.type_ == "thresholds" })

    let assert Ok(timeframe_attr) =
      dict.get(thresholds_block.attributes, "timeframe")
    timeframe_attr |> should.equal(hcl.StringLiteral(expected_timeframe))
  })
}

pub fn generate_slo_missing_values_test() {
  [
    #("threshold", common.MissingValue("threshold")),
    #("window_in_days", common.MissingValue("window_in_days")),
    #("numerator_query", common.MissingValue("numerator_query")),
    #("denominator_query", common.MissingValue("denominator_query")),
  ]
  |> list.each(fn(pair) {
    let #(missing_field, expected_error) = pair
    let ir = make_incomplete_ir(missing_field)

    datadog.generate_slo(ir)
    |> should.equal(Error(expected_error))
  })
}

// ==== Tests - generate_slos ====
// * ✅ happy path - empty list
// * ✅ happy path - multiple SLOs
// * ✅ sad path - one failure fails all
pub fn generate_slos_test() {
  // empty list
  datadog.generate_slos([])
  |> should.equal(Ok([]))

  // multiple SLOs
  let irs = [
    make_slo_ir("slo1", 99.9, 30, "q1", "q2"),
    make_slo_ir("slo2", 99.5, 7, "q3", "q4"),
  ]

  let result = datadog.generate_slos(irs)
  result |> should.be_ok

  let assert Ok(resources) = result
  list.length(resources) |> should.equal(2)

  // one failure fails all
  let irs_with_failure = [
    make_slo_ir("slo1", 99.9, 30, "q1", "q2"),
    make_incomplete_ir("threshold"),
  ]

  datadog.generate_slos(irs_with_failure)
  |> should.be_error
}

// ==== Tests - rendered output structure ====
// * ✅ renders valid HCL
pub fn generate_slo_renders_valid_hcl_test() {
  let ir =
    make_slo_ir(
      "api_availability",
      99.9,
      30,
      "sum:requests.success{service:api}.as_count()",
      "sum:requests.total{service:api}.as_count()",
    )

  let result = datadog.generate_slo(ir)
  result |> should.be_ok

  let assert Ok(resource) = result

  // Convert to block and render
  let block =
    hcl.Block(
      type_: "resource",
      labels: [resource.type_, resource.name],
      attributes: resource.attributes,
      blocks: resource.blocks,
    )

  let rendered = render.render_block(block)

  // Check key elements are present
  rendered |> string.contains("datadog_service_level_objective") |> should.be_true
  rendered |> string.contains("api_availability") |> should.be_true
  rendered |> string.contains("query") |> should.be_true
  rendered |> string.contains("thresholds") |> should.be_true
  rendered |> string.contains("99.9") |> should.be_true
  rendered |> string.contains("30d") |> should.be_true
}

