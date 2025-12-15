import caffeine_lang/common/errors
import caffeine_lang/common/helpers
import caffeine_lang/middle_end/templatizer
import gleam/dynamic
import test_helpers

// ==== Parse and Resolve Query Template ====
// * ✅ missing value tuple for a value
// * ✅ query template var incomplete, missing ending `$$`
// * ✅ happy path - no template variables
// * ✅ happy path - multiple template variables (Datadog format)
// * ✅ happy path - raw value substitution (time_slice threshold)
// * ✅ happy path - mixed raw and Datadog format
pub fn parse_and_resolve_query_template_test() {
  [
    #(
      "foo.sum$$baz->faz$$",
      [],
      Error(errors.SemanticAnalysisTemplateParseError(
        "Missing input for template: faz",
      )),
    ),
    #(
      "foo.sum$$baz",
      [],
      Error(errors.SemanticAnalysisTemplateParseError(
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
    // Raw value substitution - perfect for time_slice thresholds!
    #(
      "time_slice(query < $$threshold$$ per 10s)",
      [
        helpers.ValueTuple(
          "threshold",
          typ: helpers.Integer,
          value: dynamic.int(2_500_000),
        ),
      ],
      Ok("time_slice(query < 2500000 per 10s)"),
    ),
    // Raw value with Float
    #(
      "time_slice(query > $$threshold$$ per 5m)",
      [
        helpers.ValueTuple(
          "threshold",
          typ: helpers.Float,
          value: dynamic.float(99.5),
        ),
      ],
      Ok("time_slice(query > 99.5 per 5m)"),
    ),
    // Raw value with String
    #(
      "some_metric{status:$$status$$}",
      [
        helpers.ValueTuple(
          "status",
          typ: helpers.String,
          value: dynamic.string("active"),
        ),
      ],
      Ok("some_metric{status:active}"),
    ),
    // Mixed raw and Datadog format
    #(
      "time_slice(avg:system.cpu{$$env->environment$$} > $$threshold$$ per 300s)",
      [
        helpers.ValueTuple(
          "environment",
          typ: helpers.String,
          value: dynamic.string("production"),
        ),
        helpers.ValueTuple(
          "threshold",
          typ: helpers.Integer,
          value: dynamic.int(80),
        ),
      ],
      Ok("time_slice(avg:system.cpu{env:production} > 80 per 300s)"),
    ),
  ]
  |> test_helpers.array_based_test_executor_2(
    templatizer.parse_and_resolve_query_template,
  )
}

// ==== Parse Template Variable ====
// * ✅ parses "threshold" (no ->) -> Raw
// * ✅ parses "environment->env" -> Default
// * ✅ parses "environment->env:not" -> Not
// * ✅ rejects empty template name
// * ✅ rejects empty input name (with ->)
// * ✅ rejects empty label name (with ->)
// * ✅ rejects unknown template type
pub fn parse_template_variable_test() {
  [
    // Raw format: just the input name, no "->"
    #(
      "threshold",
      Ok(templatizer.TemplateVariable("threshold", "", templatizer.Raw)),
    ),
    #(
      "my_value",
      Ok(templatizer.TemplateVariable("my_value", "", templatizer.Raw)),
    ),
    // Datadog format: input->attr
    #(
      "bar->foo",
      Ok(templatizer.TemplateVariable("foo", "bar", templatizer.Default)),
    ),
    #(
      "bar->foo:not",
      Ok(templatizer.TemplateVariable("foo", "bar", templatizer.Not)),
    ),
    // Error cases
    #(
      "",
      Error(errors.SemanticAnalysisTemplateParseError(
        "Empty template variable name: ",
      )),
    ),
    #(
      "  ",
      Error(errors.SemanticAnalysisTemplateParseError(
        "Empty template variable name:   ",
      )),
    ),
    #(
      "->foo",
      Error(errors.SemanticAnalysisTemplateParseError(
        "Empty input name in template: ->foo",
      )),
    ),
    #(
      "foo->",
      Error(errors.SemanticAnalysisTemplateParseError(
        "Empty label name in template: foo->",
      )),
    ),
    #(
      "foo->foo:unknown",
      Error(errors.SemanticAnalysisTemplateParseError(
        "Unknown template type: unknown",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(
    templatizer.parse_template_variable,
  )
}

// ==== Parse Template Type ====
// * ✅ not
// * ✅ unknown
pub fn parse_template_type_test() {
  [
    #("not", Ok(templatizer.Not)),
    #(
      "unknown",
      Error(errors.SemanticAnalysisTemplateParseError(
        "Unknown template type: unknown",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(templatizer.parse_template_type)
}

// ==== Resolve Template ====
// * ✅ input name and value tuple label don't match
// * ✅ unsupported type - dict
// * ✅ unsupported type - optional dict
// * ✅ resolves boolean
// * ✅ resolves int
// * ✅ resolves float
// * ✅ resolves string
// * ✅ resolves list of booleans
// * ✅ resolves list of ints
// * ✅ resolves list of floats
// * ✅ resolves list of strings
// * ✅ resolves optional string with value
// * ✅ resolves optional string with none (returns empty string)
// * ✅ resolves optional list with value
// * ✅ resolves optional list with none (returns empty string)
// * ✅ resolves defaulted integer with value
// * ✅ resolves defaulted integer with none (uses default)
// * ✅ resolves defaulted string with value
// * ✅ resolves defaulted string with none (uses default)
// * ✅ resolves defaulted with Raw template type and nil value
// * ✅ unsupported type - defaulted dict
pub fn resolve_template_test() {
  [
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "bar",
        typ: helpers.Boolean,
        value: dynamic.bool(True),
      ),
      Error(errors.SemanticAnalysisTemplateResolutionError(
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
      Error(errors.SemanticAnalysisTemplateResolutionError(
        "Unsupported templatized variable type: Dict(String, Boolean). Dict support is pending, open an issue if this is a desired use case.",
      )),
    ),
    // Optional Dict is also unsupported
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: helpers.Optional(helpers.Dict(helpers.String, helpers.String)),
        value: dynamic.array([]),
      ),
      Error(errors.SemanticAnalysisTemplateResolutionError(
        "Unsupported templatized variable type: Optional(Dict(String, String)). Dict support is pending, open an issue if this is a desired use case.",
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
    // Optional string with value
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: helpers.Optional(helpers.String),
        value: dynamic.string("salad"),
      ),
      Ok("foo:salad"),
    ),
    // Optional string with None - returns empty string
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: helpers.Optional(helpers.String),
        value: dynamic.nil(),
      ),
      Ok(""),
    ),
    // Optional integer with value
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: helpers.Optional(helpers.Integer),
        value: dynamic.int(42),
      ),
      Ok("foo:42"),
    ),
    // Optional list with value
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: helpers.Optional(helpers.List(helpers.String)),
        value: dynamic.list([dynamic.string("a"), dynamic.string("b")]),
      ),
      Ok("foo IN (a, b)"),
    ),
    // Optional list with None - returns empty string
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: helpers.Optional(helpers.List(helpers.String)),
        value: dynamic.nil(),
      ),
      Ok(""),
    ),
    // Defaulted integer with value - uses provided value
    #(
      templatizer.TemplateVariable(
        "threshold",
        "threshold",
        templatizer.Default,
      ),
      helpers.ValueTuple(
        label: "threshold",
        typ: helpers.Defaulted(helpers.Integer, "2500000"),
        value: dynamic.int(1_000_000),
      ),
      Ok("threshold:1000000"),
    ),
    // Defaulted integer with None - uses default value
    #(
      templatizer.TemplateVariable(
        "threshold",
        "threshold",
        templatizer.Default,
      ),
      helpers.ValueTuple(
        label: "threshold",
        typ: helpers.Defaulted(helpers.Integer, "2500000"),
        value: dynamic.nil(),
      ),
      Ok("threshold:2500000"),
    ),
    // Defaulted string with value
    #(
      templatizer.TemplateVariable("env", "env", templatizer.Default),
      helpers.ValueTuple(
        label: "env",
        typ: helpers.Defaulted(helpers.String, "production"),
        value: dynamic.string("staging"),
      ),
      Ok("env:staging"),
    ),
    // Defaulted string with None - uses default value
    #(
      templatizer.TemplateVariable("env", "env", templatizer.Default),
      helpers.ValueTuple(
        label: "env",
        typ: helpers.Defaulted(helpers.String, "production"),
        value: dynamic.nil(),
      ),
      Ok("env:production"),
    ),
    // Defaulted with Raw template type and nil value - uses default
    #(
      templatizer.TemplateVariable("threshold", "", templatizer.Raw),
      helpers.ValueTuple(
        label: "threshold",
        typ: helpers.Defaulted(helpers.Integer, "2500000000"),
        value: dynamic.nil(),
      ),
      Ok("2500000000"),
    ),
    // Defaulted Dict is unsupported
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: helpers.Defaulted(
          helpers.Dict(helpers.String, helpers.String),
          "{}",
        ),
        value: dynamic.nil(),
      ),
      Error(errors.SemanticAnalysisTemplateResolutionError(
        "Unsupported templatized variable type: Defaulted(Dict(String, String), {}). Dict support is pending, open an issue if this is a desired use case.",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_2(templatizer.resolve_template)
}

// ==== Resolve String Value ====
// * ✅ Raw: just the value itself
// * ✅ Default: "attr:value" (wildcards preserved)
// * ✅ Not: "!attr:value" (wildcards preserved)
pub fn resolve_string_value_test() {
  [
    // Raw: just returns the value
    #(
      templatizer.TemplateVariable("threshold", "", templatizer.Raw),
      "2500000",
      "2500000",
    ),
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
  |> test_helpers.array_based_test_executor_2(templatizer.resolve_string_value)
}

// ==== Resolve List Value ====
// * ✅ Raw: "v1, v2, v3" (comma-separated)
// * ✅ Default: "attr IN (v1, v2, v3)"
// * ✅ Not: "attr NOT IN (v1, v2)"
pub fn resolve_list_value_test() {
  [
    // Raw: just comma-separated values
    #(
      templatizer.TemplateVariable("values", "", templatizer.Raw),
      ["bar", "baz"],
      "bar, baz",
    ),
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
  |> test_helpers.array_based_test_executor_2(templatizer.resolve_list_value)
}
