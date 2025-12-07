import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/middle_end
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
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

// ==== Tests - execute with template variables ====
// * ✅ happy path - templates replaced with string values from IR
// * ✅ happy path - no templates (queries unchanged)
// * ✅ sad path - missing attribute
fn make_slo_ir_with_string_values(
  value: String,
  queries: dict.Dict(String, String),
  extra_strings: List(#(String, String)),
) -> middle_end.IntermediateRepresentation {
  let queries_value =
    queries
    |> dict.to_list
    |> list.map(fn(pair) {
      let #(k, v) = pair
      #(dynamic.string(k), dynamic.string(v))
    })
    |> dynamic.properties

  let base_values = [
    middle_end.ValueTuple(
      label: "vendor",
      typ: helpers.String,
      value: dynamic.string("datadog"),
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
  ]

  let extra_values =
    extra_strings
    |> list.map(fn(pair) {
      let #(label, val) = pair
      middle_end.ValueTuple(label:, typ: helpers.String, value: dynamic.string(val))
    })

  middle_end.IntermediateRepresentation(
    expectation_name: "test_slo",
    artifact_ref: "SLO",
    values: list.append(base_values, extra_values),
  )
}

pub fn execute_slo_datadog_replaces_templates_test() {
  let queries =
    dict.from_list([
      #("numerator", "sum:requests.success{host:$$hostname->h$$}"),
      #("denominator", "sum:requests.total{host:$$hostname->h$$}"),
    ])
  // hostname is a string value in the IR that will be used for template replacement
  let ir =
    make_slo_ir_with_string_values(
      "numerator / denominator",
      queries,
      [#("hostname", "api.example.com")],
    )

  let result = middle_end.execute([ir])
  result |> should.be_ok

  let assert Ok([resolved_ir]) = result

  // Find and check numerator_query
  let assert Ok(num_vt) =
    resolved_ir.values |> list.find(fn(vt) { vt.label == "numerator_query" })
  let assert Ok(num_query) = decode.run(num_vt.value, decode.string)
  num_query |> should.equal("sum:requests.success{host:api.example.com}")

  // Find and check denominator_query
  let assert Ok(denom_vt) =
    resolved_ir.values |> list.find(fn(vt) { vt.label == "denominator_query" })
  let assert Ok(denom_query) = decode.run(denom_vt.value, decode.string)
  denom_query |> should.equal("sum:requests.total{host:api.example.com}")
}

pub fn execute_slo_datadog_no_templates_unchanged_test() {
  // Queries without template variables
  let queries =
    dict.from_list([
      #("numerator", "sum:requests.success{service:api}"),
      #("denominator", "sum:requests.total{service:api}"),
    ])

  let ir = make_slo_ir_with_value_queries("datadog", "numerator / denominator", queries)

  let result = middle_end.execute([ir])
  result |> should.be_ok

  let assert Ok([resolved_ir]) = result

  // Queries should be unchanged since no templates
  let assert Ok(num_vt) =
    resolved_ir.values |> list.find(fn(vt) { vt.label == "numerator_query" })
  let assert Ok(num_query) = decode.run(num_vt.value, decode.string)
  num_query |> should.equal("sum:requests.success{service:api}")
}

pub fn execute_slo_datadog_missing_attribute_test() {
  let queries =
    dict.from_list([
      #("numerator", "sum:requests{host:$$missing_attr->h$$}"),
      #("denominator", "sum:total"),
    ])
  // No extra string values - missing_attr won't be found
  let ir = make_slo_ir_with_string_values("numerator / denominator", queries, [])

  let result = middle_end.execute([ir])
  result |> should.be_error

  let assert Error(middle_end.QueryResolutionError(msg)) = result
  msg |> should.equal("Missing template attribute: missing_attr")
}

// ==== Tests - parse_template_variable ====
// Happy paths:
// * ✅ standard format
// * ✅ underscores in both parts
// * ✅ multiple arrows (first one is separator)
// Sad paths:
// * ✅ no arrow
// * ✅ empty attribute
// * ✅ empty template
pub fn parse_template_variable_happy_path_test() {
  // standard format
  middle_end.parse_template_variable("peer_hostname->host")
  |> should.equal(Ok(#("peer_hostname", "host")))

  // underscores in both
  middle_end.parse_template_variable("my_attr->my_template")
  |> should.equal(Ok(#("my_attr", "my_template")))

  // multiple arrows - first one is separator
  middle_end.parse_template_variable("attr->template->extra")
  |> should.equal(Ok(#("attr", "template->extra")))
}

pub fn parse_template_variable_sad_path_test() {
  // no arrow
  middle_end.parse_template_variable("noarrow")
  |> should.equal(Error(middle_end.InvalidVariableFormat("noarrow")))

  // empty attribute
  middle_end.parse_template_variable("->template")
  |> should.equal(Error(middle_end.InvalidVariableFormat("->template")))

  // empty template
  middle_end.parse_template_variable("attr->")
  |> should.equal(Error(middle_end.InvalidVariableFormat("attr->")))
}

// ==== Tests - extract_template_variables_from_string ====
// Happy paths:
// * ✅ single variable
// * ✅ multiple variables
// * ✅ no variables
// * ✅ real query
// * ✅ adjacent variables
// Sad paths:
// * ✅ unterminated variable
// * ✅ invalid variable format (no arrow)
// * ✅ empty variable
// * ✅ single $ ignored
// * ✅ empty attribute
// * ✅ empty template
pub fn extract_template_variables_happy_path_test() {
  // single variable
  middle_end.extract_template_variables_from_string("$$foo->bar$$")
  |> should.equal(Ok(["foo->bar"]))

  // multiple variables
  middle_end.extract_template_variables_from_string(
    "prefix $$a->x$$ middle $$b->y$$ suffix",
  )
  |> should.equal(Ok(["a->x", "b->y"]))

  // no variables
  middle_end.extract_template_variables_from_string("plain string")
  |> should.equal(Ok([]))

  // real query
  middle_end.extract_template_variables_from_string(
    "sum:hits{host:$$peer_hostname->host$$}",
  )
  |> should.equal(Ok(["peer_hostname->host"]))

  // adjacent variables
  middle_end.extract_template_variables_from_string("$$a->x$$$$b->y$$")
  |> should.equal(Ok(["a->x", "b->y"]))

  // single $ ignored
  middle_end.extract_template_variables_from_string("$foo->bar$")
  |> should.equal(Ok([]))
}

pub fn extract_template_variables_sad_path_test() {
  // unterminated variable
  middle_end.extract_template_variables_from_string("$$foo->bar")
  |> should.equal(Error(middle_end.UnterminatedVariable("foo->bar")))

  // invalid variable format (no arrow)
  middle_end.extract_template_variables_from_string("$$noarrow$$")
  |> should.equal(Error(middle_end.InvalidVariableFormat("noarrow")))

  // empty variable
  middle_end.extract_template_variables_from_string("$$$$")
  |> should.equal(Error(middle_end.InvalidVariableFormat("")))

  // empty attribute
  middle_end.extract_template_variables_from_string("$$->template$$")
  |> should.equal(Error(middle_end.InvalidVariableFormat("->template")))

  // empty template
  middle_end.extract_template_variables_from_string("$$attr->$$")
  |> should.equal(Error(middle_end.InvalidVariableFormat("attr->")))
}

// ==== Tests - replace_template_variables ====
// Happy paths:
// * ✅ single replacement
// * ✅ multiple replacements
// * ✅ no variables unchanged
// * ✅ same variable twice
// Sad paths:
// * ✅ missing attribute in dict
// * ✅ invalid variable format
// * ✅ unterminated variable
pub fn replace_template_variables_happy_path_test() {
  // single replacement
  middle_end.replace_template_variables(
    "$$name->n$$",
    dict.from_list([#("name", "alice")]),
  )
  |> should.equal(Ok("alice"))

  // multiple replacements
  middle_end.replace_template_variables(
    "$$a->x$$ and $$b->y$$",
    dict.from_list([#("a", "1"), #("b", "2")]),
  )
  |> should.equal(Ok("1 and 2"))

  // no variables unchanged
  middle_end.replace_template_variables("plain", dict.from_list([]))
  |> should.equal(Ok("plain"))

  // same variable twice
  middle_end.replace_template_variables(
    "$$x->a$$ $$x->b$$",
    dict.from_list([#("x", "val")]),
  )
  |> should.equal(Ok("val val"))

  // real query example
  middle_end.replace_template_variables(
    "sum:http.requests{host:$$peer_hostname->host$$ AND env:$$environment->env$$}",
    dict.from_list([#("peer_hostname", "api.example.com"), #("environment", "prod")]),
  )
  |> should.equal(Ok("sum:http.requests{host:api.example.com AND env:prod}"))
}

pub fn replace_template_variables_sad_path_test() {
  // missing attribute in dict
  middle_end.replace_template_variables(
    "$$missing->m$$",
    dict.from_list([]),
  )
  |> should.equal(Error(middle_end.MissingAttribute("missing")))

  // invalid variable format
  middle_end.replace_template_variables(
    "$$noarrow$$",
    dict.from_list([]),
  )
  |> should.equal(Error(middle_end.InvalidVariableFormat("noarrow")))

  // unterminated variable
  middle_end.replace_template_variables(
    "$$foo->bar",
    dict.from_list([]),
  )
  |> should.equal(Error(middle_end.UnterminatedVariable("foo->bar")))
}

// ==== Tests - format_template_error ====
pub fn format_template_error_test() {
  [
    #(
      middle_end.InvalidVariableFormat("bad"),
      "Invalid template variable format: bad",
    ),
    #(middle_end.MissingAttribute("foo"), "Missing template attribute: foo"),
    #(
      middle_end.UnterminatedVariable("bar->baz"),
      "Unterminated template variable: $$bar->baz",
    ),
  ]
  |> list.each(fn(pair) {
    let #(error, expected) = pair
    middle_end.format_template_error(error)
    |> should.equal(expected)
  })
}
