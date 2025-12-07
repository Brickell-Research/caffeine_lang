import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/middle_end
import gleam/dict
import gleam/dynamic
import gleam/list
import gleeunit/should

// ==== Tests - resolve_queries ====
// * ✅ happy path - simple numerator / denominator
// * ✅ happy path - custom variable names
// * ✅ happy path - parenthesized expression
// * ✅ happy path - complex denominator expression
// * ✅ sad path - invalid CQL expression (not a division)
// * ✅ sad path - query key not found in queries dict
pub fn resolve_queries_happy_path_test() {
  let queries =
    dict.from_list([
      #("numerator", "sum:requests.success{service:api}"),
      #("denominator", "sum:requests.total{service:api}"),
    ])

  // Simple division
  middle_end.resolve_queries("numerator / denominator", queries)
  |> should.equal(Ok(#(
    "sum:requests.success{service:api}",
    "sum:requests.total{service:api}",
  )))
}

pub fn resolve_queries_custom_variable_names_test() {
  let queries =
    dict.from_list([
      #("good", "sum:events.success{env:prod}"),
      #("total", "sum:events.all{env:prod}"),
    ])

  middle_end.resolve_queries("good / total", queries)
  |> should.equal(Ok(#(
    "sum:events.success{env:prod}",
    "sum:events.all{env:prod}",
  )))
}

pub fn resolve_queries_parenthesized_test() {
  let queries =
    dict.from_list([#("numerator", "query1"), #("denominator", "query2")])

  // CQL preserves parentheses in the output
  middle_end.resolve_queries("(numerator) / (denominator)", queries)
  |> should.equal(Ok(#("(query1)", "(query2)")))
}

pub fn resolve_queries_complex_denominator_test() {
  let queries =
    dict.from_list([
      #("numerator", "sum:requests.success{service:api}"),
      #("denominator_1", "sum:requests.total{service:api,status:2xx}"),
      #("denominator_2", "sum:requests.total{service:api,status:3xx}"),
    ])

  // Complex expression: numerator / (denominator_1 + denominator_2)
  middle_end.resolve_queries(
    "numerator / (denominator_1 + denominator_2)",
    queries,
  )
  |> should.equal(Ok(#(
    "sum:requests.success{service:api}",
    "(sum:requests.total{service:api,status:2xx} + sum:requests.total{service:api,status:3xx})",
  )))
}

pub fn resolve_queries_invalid_cql_test() {
  let queries =
    dict.from_list([#("numerator", "query1"), #("denominator", "query2")])

  // Not a division - should fail with ResolveError
  [
    "numerator + denominator",
    "numerator * denominator",
    "numerator - denominator",
    "just_a_word",
  ]
  |> list.each(fn(value) {
    let result = middle_end.resolve_queries(value, queries)
    result |> should.be_error

    let assert Error(middle_end.ResolveError(_)) = result
  })
}

pub fn resolve_queries_missing_query_key_test() {
  let queries = dict.from_list([#("numerator", "query1")])

  // denominator key missing from queries dict
  middle_end.resolve_queries("numerator / denominator", queries)
  |> should.equal(Error(middle_end.MissingQueryKey("denominator")))

  // numerator key missing
  let queries2 = dict.from_list([#("denominator", "query2")])
  middle_end.resolve_queries("numerator / denominator", queries2)
  |> should.equal(Error(middle_end.MissingQueryKey("numerator")))
}

// ==== Tests - format_resolve_error ====
pub fn format_resolve_error_test() {
  [
    #(middle_end.ParseError("bad syntax"), "CQL parse error: bad syntax"),
    #(middle_end.ResolveError("not a division"), "CQL resolve error: not a division"),
    #(middle_end.MissingQueryKey("foo"), "Missing query key: foo"),
  ]
  |> list.each(fn(pair) {
    let #(error, expected) = pair
    middle_end.format_resolve_error(error)
    |> should.equal(expected)
  })
}

// ==== Tests - execute ====
// * ✅ happy path - SLO with datadog vendor resolves queries
// * ✅ happy path - non-SLO artifacts pass through unchanged
// * ✅ happy path - SLO with non-datadog vendor passes through unchanged
// * ✅ sad path - SLO with missing value field
// * ✅ sad path - SLO with missing queries field
fn make_slo_ir_with_value_queries(
  vendor: String,
  value: String,
  queries: dict.Dict(String, String),
) -> middle_end.IntermediateRepresentation {
  let queries_value =
    queries
    |> dict.to_list
    |> list.map(fn(pair) {
      let #(k, v) = pair
      #(dynamic.string(k), dynamic.string(v))
    })
    |> dynamic.properties

  middle_end.IntermediateRepresentation(
    expectation_name: "test_slo",
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
        label: "value",
        typ: helpers.String,
        value: dynamic.string(value),
      ),
      middle_end.ValueTuple(
        label: "queries",
        typ: helpers.Dict(helpers.String, helpers.String),
        value: queries_value,
      ),
    ],
  )
}

pub fn execute_slo_datadog_resolves_queries_test() {
  let queries =
    dict.from_list([
      #("numerator", "sum:requests.success{service:api}"),
      #("denominator", "sum:requests.total{service:api}"),
    ])

  let ir = make_slo_ir_with_value_queries("datadog", "numerator / denominator", queries)

  let result = middle_end.execute([ir])
  result |> should.be_ok

  let assert Ok([resolved_ir]) = result

  // Should have numerator_query and denominator_query, not value and queries
  let labels = resolved_ir.values |> list.map(fn(vt) { vt.label })
  labels |> list.contains("numerator_query") |> should.be_true
  labels |> list.contains("denominator_query") |> should.be_true
  labels |> list.contains("value") |> should.be_false
  labels |> list.contains("queries") |> should.be_false
}

pub fn execute_non_slo_passes_through_test() {
  let ir =
    middle_end.IntermediateRepresentation(
      expectation_name: "some_other_artifact",
      artifact_ref: "Monitor",
      values: [
        middle_end.ValueTuple(
          label: "name",
          typ: helpers.String,
          value: dynamic.string("test"),
        ),
      ],
    )

  let result = middle_end.execute([ir])
  result |> should.be_ok

  let assert Ok([unchanged_ir]) = result
  unchanged_ir |> should.equal(ir)
}

pub fn execute_slo_non_datadog_passes_through_test() {
  let queries = dict.from_list([#("a", "b")])
  let ir = make_slo_ir_with_value_queries("other_vendor", "a / b", queries)

  let result = middle_end.execute([ir])
  result |> should.be_ok

  let assert Ok([unchanged_ir]) = result
  // Should still have value and queries (not resolved)
  let labels = unchanged_ir.values |> list.map(fn(vt) { vt.label })
  labels |> list.contains("value") |> should.be_true
  labels |> list.contains("queries") |> should.be_true
}

pub fn execute_slo_datadog_missing_value_test() {
  let queries_value =
    dynamic.properties([
      #(dynamic.string("numerator"), dynamic.string("q1")),
      #(dynamic.string("denominator"), dynamic.string("q2")),
    ])

  let ir =
    middle_end.IntermediateRepresentation(
      expectation_name: "test",
      artifact_ref: "SLO",
      values: [
        middle_end.ValueTuple(
          label: "vendor",
          typ: helpers.String,
          value: dynamic.string("datadog"),
        ),
        middle_end.ValueTuple(
          label: "queries",
          typ: helpers.Dict(helpers.String, helpers.String),
          value: queries_value,
        ),
      ],
    )

  let result = middle_end.execute([ir])
  result |> should.be_error

  let assert Error(middle_end.QueryResolutionError(msg)) = result
  msg |> should.equal("Missing 'value' field for SLO")
}

pub fn execute_slo_datadog_missing_queries_test() {
  let ir =
    middle_end.IntermediateRepresentation(
      expectation_name: "test",
      artifact_ref: "SLO",
      values: [
        middle_end.ValueTuple(
          label: "vendor",
          typ: helpers.String,
          value: dynamic.string("datadog"),
        ),
        middle_end.ValueTuple(
          label: "value",
          typ: helpers.String,
          value: dynamic.string("numerator / denominator"),
        ),
      ],
    )

  let result = middle_end.execute([ir])
  result |> should.be_error

  let assert Error(middle_end.QueryResolutionError(msg)) = result
  msg |> should.equal("Missing 'queries' field for SLO")
}
