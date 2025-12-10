import caffeine_lang/common/errors
import caffeine_lang/common/helpers
import caffeine_lang/middle_end/templatizer
import gleam/dynamic
import gleam/list
import gleeunit/should

// ==== Parse and Resolve Query Template ====
// * ✅ missing value tuple for a value
// * ✅ query template var incomplete, missing ending `$$`
// * ✅ happy path - no template variables
// * ✅ happy path - multiple template variables
pub fn parse_and_resolve_query_template_test() {
  [
    #(
      "foo.sum$$baz->faz$$",
      [],
      Error(errors.TemplateParseError("Missing input for template: faz")),
    ),
    #(
      "foo.sum$$baz",
      [],
      Error(errors.TemplateParseError(
        "Unexpected incomplete `$$` for substring: foo.sum$$baz",
      )),
    ),
    #("foo", [], Ok("foo")),
    #(
      "foo.sum{$$foo->bar:not$$ AND $$baz->faz$$}",
      [
        helpers.ValueTuple(
          "bar",
          typ: helpers.String,
          value: dynamic.string("pizza"),
        ),
        helpers.ValueTuple(
          "faz",
          typ: helpers.List(helpers.Integer),
          value: dynamic.list([
            dynamic.int(10),
            dynamic.int(11),
            dynamic.int(12),
          ]),
        ),
      ],
      Ok("foo.sum{!foo:pizza AND baz IN (10, 11, 12)}"),
    ),
  ]
  |> list.each(fn(tuple) {
    let #(input_1, input_2, expected) = tuple

    templatizer.parse_and_resolve_query_template(input_1, input_2)
    |> should.equal(expected)
  })
}

// ==== Parse Template Variable ====
// * ✅ parses "environment->env" -> Default
// * ✅ parses "environment->env:not" -> Not
// * ✅ rejects missing "->"
// * ✅ rejects empty input name
// * ✅ rejects empty label name
// * ✅ rejects unknown template type
pub fn parse_template_variable_test() {
  [
    #(
      "bar->foo",
      Ok(templatizer.TemplateVariable("foo", "bar", templatizer.Default)),
    ),
    #(
      "bar->foo:not",
      Ok(templatizer.TemplateVariable("foo", "bar", templatizer.Not)),
    ),
    #(
      "foofoo",
      Error(errors.TemplateParseError(
        "Invalid template format, missing '->': foofoo",
      )),
    ),

    #(
      "->foo",
      Error(errors.TemplateParseError("Empty input name in template: ->foo")),
    ),
    #(
      "foo->",
      Error(errors.TemplateParseError("Empty label name in template: foo->")),
    ),
    #(
      "foo->foo:unknown",
      Error(errors.TemplateParseError("Unknown template type: unknown")),
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair

    templatizer.parse_template_variable(input)
    |> should.equal(expected)
  })
}

// ==== Parse Template Type ====
// * ✅ not
// * ✅ unknown
pub fn parse_template_type_test() {
  [
    #("not", Ok(templatizer.Not)),
    #(
      "unknown",
      Error(errors.TemplateParseError("Unknown template type: unknown")),
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair

    templatizer.parse_template_type(input)
    |> should.equal(expected)
  })
}

// ==== Resolve Template ====
// * ✅ input name and value tuple label don't match
// * ✅ unsupported type - dict
// * ✅ resolves boolean
// * ✅ resolves int
// * ✅ resolves float
// * ✅ resolves string
// * ✅ resolves list of booleans
// * ✅ resolves list of ints
// * ✅ resolves list of floats
// * ✅ resolves list of strings
pub fn resolve_template_test() {
  [
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "bar",
        typ: helpers.Boolean,
        value: dynamic.bool(True),
      ),
      Error(errors.TemplateResolutionError(
        "Mismatch between template input name (foo) and input value label (bar).",
      )),
    ),
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: helpers.Dict(helpers.String, helpers.Boolean),
        // technically invalud data point here but whatever, test still serves its purpose
        value: dynamic.array([]),
      ),
      Error(errors.TemplateResolutionError(
        "Unsupported templatized variable type: Dict(String, Boolean). Dict support is pending, open an issue if this is a desired use case.",
      )),
    ),
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: helpers.Boolean,
        value: dynamic.bool(True),
      ),
      Ok("foo:True"),
    ),
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: helpers.Integer,
        value: dynamic.int(10),
      ),
      Ok("foo:10"),
    ),
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: helpers.Float,
        value: dynamic.float(11.7),
      ),
      Ok("foo:11.7"),
    ),
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: helpers.String,
        value: dynamic.string("salad"),
      ),
      Ok("foo:salad"),
    ),
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: helpers.List(helpers.Boolean),
        value: dynamic.list([dynamic.bool(True), dynamic.bool(False)]),
      ),
      Ok("foo IN (True, False)"),
    ),
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: helpers.List(helpers.Integer),
        value: dynamic.list([dynamic.int(10), dynamic.int(11)]),
      ),
      Ok("foo IN (10, 11)"),
    ),
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: helpers.List(helpers.Float),
        value: dynamic.list([dynamic.float(11.7), dynamic.float(7.11)]),
      ),
      Ok("foo IN (11.7, 7.11)"),
    ),
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: helpers.List(helpers.String),
        value: dynamic.list([dynamic.string("salad"), dynamic.string("pizza")]),
      ),
      Ok("foo IN (salad, pizza)"),
    ),
  ]
  |> list.each(fn(tuple) {
    let #(input_1, input_2, expected) = tuple

    templatizer.resolve_template(input_1, input_2)
    |> should.equal(expected)
  })
}

// ==== Resolve String Value ====
// * ✅ Default: "attr:value" (wildcards preserved)
// * ✅ Not: "!attr:value" (wildcards preserved)
pub fn resolve_string_value_test() {
  [
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      "bar",
      "foo:bar",
    ),
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Not),
      "bar",
      "!foo:bar",
    ),
  ]
  |> list.each(fn(tuple) {
    let #(input_1, input_2, expected) = tuple

    templatizer.resolve_string_value(input_1, input_2)
    |> should.equal(expected)
  })
}

// ==== Resolve List Value ====
// * ✅ Default: "attr IN (v1, v2, v3)"
// * ✅ Not: "attr NOT IN (v1, v2)"
pub fn resolve_list_value_test() {
  [
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      ["bar", "baz"],
      "foo IN (bar, baz)",
    ),
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Not),
      ["bar", "baz"],
      "foo NOT IN (bar, baz)",
    ),
  ]
  |> list.each(fn(tuple) {
    let #(input_1, input_2, expected) = tuple

    templatizer.resolve_list_value(input_1, input_2)
    |> should.equal(expected)
  })
}
