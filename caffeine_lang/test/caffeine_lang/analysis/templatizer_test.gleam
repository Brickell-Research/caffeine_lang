import caffeine_lang/analysis/templatizer
import caffeine_lang/errors
import caffeine_lang/helpers
import caffeine_lang/types
import caffeine_lang/value
import gleam/dict
import gleam/option
import gleam/set
import test_helpers

// ==== Cleanup Empty Template Artifacts ====
// * ✅ no artifacts - unchanged
// * ✅ trailing comma in braces: ", }" and ",}"
// * ✅ leading comma in braces: "{, " and "{,"
// * ✅ trailing comma in parens: ", )" and ",)"
// * ✅ leading comma in parens: "(, " and "(,"
// * ✅ consecutive commas: ", ," and ",,"
// * ✅ AND artifacts: " AND }", "{ AND ", " AND  AND "
// * ✅ all empty in braces (two optionals)
// * ✅ all empty in parens (two optionals)
// * ✅ multiple artifacts in one query
// * ✅ 3 consecutive empty optionals in braces
// * ✅ 4 consecutive empty optionals in braces
// * ✅ 3 consecutive empty optionals in parens
// * ✅ multiple AND all empty
// * ✅ mixed artifacts in complex query (multi-pass)
pub fn cleanup_empty_template_artifacts_test() {
  [
    // No artifacts - unchanged
    #("no artifacts - unchanged", "metric{env:prod}", "metric{env:prod}"),
    // Trailing comma in braces
    #(
      "trailing comma in braces: ', }'",
      "metric{env:prod, }",
      "metric{env:prod}",
    ),
    #("trailing comma in braces: ',}'", "metric{env:prod,}", "metric{env:prod}"),
    // Leading comma in braces
    #(
      "leading comma in braces: '{, '",
      "metric{, env:prod}",
      "metric{env:prod}",
    ),
    #("leading comma in braces: '{,'", "metric{,env:prod}", "metric{env:prod}"),
    // Trailing comma in parens
    #("trailing comma in parens: ', )'", "tag IN (a, b, )", "tag IN (a, b)"),
    #("trailing comma in parens: ',)'", "tag IN (a, b,)", "tag IN (a, b)"),
    // Leading comma in parens
    #("leading comma in parens: '(, '", "tag IN (, a, b)", "tag IN (a, b)"),
    #("leading comma in parens: '(,'", "tag IN (,a, b)", "tag IN (a, b)"),
    // Consecutive commas (middle empty)
    #(
      "consecutive commas: ', ,'",
      "metric{env:prod, , team:platform}",
      "metric{env:prod, team:platform}",
    ),
    #(
      "consecutive commas: ',,'",
      "metric{env:prod,,team:platform}",
      "metric{env:prod,team:platform}",
    ),
    // AND artifacts
    #("AND artifacts: ' AND }'", "metric{env:prod AND }", "metric{env:prod}"),
    #("AND artifacts: '{ AND '", "metric{ AND env:prod}", "metric{env:prod}"),
    #(
      "AND artifacts: ' AND  AND '",
      "metric{env:prod AND  AND team:platform}",
      "metric{env:prod AND team:platform}",
    ),
    // All empty in braces (two optionals)
    #("all empty in braces (two optionals)", "metric{, }", "metric{}"),
    // All empty in parens (two optionals)
    #("all empty in parens (two optionals)", "tag IN (, )", "tag IN ()"),
    // Multiple artifacts in one query
    #(
      "multiple artifacts in one query",
      "avg:my.metric{, env:prod, }.as_count()",
      "avg:my.metric{env:prod}.as_count()",
    ),
    // 3 consecutive empty optionals in braces
    #("3 consecutive empty optionals in braces", "metric{, , }", "metric{}"),
    // 4 consecutive empty optionals in braces
    #("4 consecutive empty optionals in braces", "metric{, , , }", "metric{}"),
    // 3 consecutive empty optionals in parens
    #("3 consecutive empty optionals in parens", "tag IN (, , )", "tag IN ()"),
    // Multiple AND all empty
    #("multiple AND all empty", "metric{ AND  AND  AND }", "metric{}"),
    // Mixed artifacts in complex query (multi-pass)
    #(
      "mixed artifacts in complex query (multi-pass)",
      "avg:m{, , env:prod, }.rollup(avg, )",
      "avg:m{env:prod}.rollup(avg)",
    ),
  ]
  |> test_helpers.array_based_test_executor_1(
    templatizer.cleanup_empty_template_artifacts,
  )
}

// ==== Parse and Resolve Query Template ====
// * ✅ missing value tuple for a value
// * ✅ query template var incomplete, missing ending `$$`
// * ✅ happy path - no template variables
// * ✅ happy path - multiple template variables (Datadog format)
// * ✅ happy path - raw value substitution (time_slice threshold)
// * ✅ happy path - mixed raw and Datadog format
// * ✅ happy path - refinement type with Defaulted inner (value provided)
// * ✅ happy path - refinement type with Defaulted inner (None uses default)
// * ✅ happy path - optional field at end resolves to empty (no hanging comma)
// * ✅ happy path - optional field at start resolves to empty (no hanging comma)
// * ✅ happy path - optional field in middle resolves to empty (no double comma)
// * ✅ happy path - all optional fields empty (no dangling commas)
// * ✅ happy path - optional list field with None value (no hanging comma)
// * ✅ happy path - optional with AND operator and empty field
// * ✅ happy path - 3 optional fields all empty (multi-pass cleanup)
// * ✅ happy path - optional with Not template type and None value
// * ✅ happy path - optional list with Not template type and None value
// * ✅ happy path - mixed some empty some provided with AND operator
// * ✅ happy path - optional raw value with None
pub fn parse_and_resolve_query_template_test() {
  [
    #(
      "missing value tuple for a value",
      "foo.sum$$baz->faz$$",
      [],
      Error(errors.SemanticAnalysisTemplateParseError(
        msg: "test - Missing input for template: faz",
        context: errors.ErrorContext(
          ..errors.empty_context(),
          identifier: option.Some("test"),
        ),
      )),
    ),
    #(
      "query template var incomplete, missing ending $$",
      "foo.sum$$baz",
      [],
      Error(errors.SemanticAnalysisTemplateParseError(
        msg: "test - Unexpected incomplete `$$` for substring: foo.sum$$baz",
        context: errors.ErrorContext(
          ..errors.empty_context(),
          identifier: option.Some("test"),
        ),
      )),
    ),
    #("no template variables", "foo", [], Ok("foo")),
    #(
      "multiple template variables (Datadog format)",
      "foo.sum{$$foo->bar:not$$ AND $$baz->faz$$}",
      [
        helpers.ValueTuple(
          "bar",
          typ: types.PrimitiveType(types.String),
          value: value.StringValue("pizza"),
        ),
        helpers.ValueTuple(
          "faz",
          typ: types.CollectionType(
            types.List(types.PrimitiveType(types.NumericType(types.Integer))),
          ),
          value: value.ListValue([
            value.IntValue(10),
            value.IntValue(11),
            value.IntValue(12),
          ]),
        ),
      ],
      Ok("foo.sum{!foo:pizza AND baz IN (10, 11, 12)}"),
    ),
    // Raw value substitution - perfect for time_slice thresholds!
    #(
      "raw value substitution (time_slice threshold)",
      "time_slice(query < $$threshold$$ per 10s)",
      [
        helpers.ValueTuple(
          "threshold",
          typ: types.PrimitiveType(types.NumericType(types.Integer)),
          value: value.IntValue(2_500_000),
        ),
      ],
      Ok("time_slice(query < 2500000 per 10s)"),
    ),
    // Raw value with Float
    #(
      "mixed raw and Datadog format - float",
      "time_slice(query > $$threshold$$ per 5m)",
      [
        helpers.ValueTuple(
          "threshold",
          typ: types.PrimitiveType(types.NumericType(types.Float)),
          value: value.FloatValue(99.5),
        ),
      ],
      Ok("time_slice(query > 99.5 per 5m)"),
    ),
    // Raw value with String
    #(
      "mixed raw and Datadog format - string",
      "some_metric{status:$$status$$}",
      [
        helpers.ValueTuple(
          "status",
          typ: types.PrimitiveType(types.String),
          value: value.StringValue("active"),
        ),
      ],
      Ok("some_metric{status:active}"),
    ),
    // Mixed raw and Datadog format
    #(
      "mixed raw and Datadog format",
      "time_slice(avg:system.cpu{$$env->environment$$} > $$threshold$$ per 300s)",
      [
        helpers.ValueTuple(
          "environment",
          typ: types.PrimitiveType(types.String),
          value: value.StringValue("production"),
        ),
        helpers.ValueTuple(
          "threshold",
          typ: types.PrimitiveType(types.NumericType(types.Integer)),
          value: value.IntValue(80),
        ),
      ],
      Ok("time_slice(avg:system.cpu{env:production} > 80 per 300s)"),
    ),
    // Refinement type with Defaulted inner - value provided
    #(
      "refinement type with Defaulted inner (value provided)",
      "metric{$$env->environment$$}",
      [
        helpers.ValueTuple(
          "environment",
          typ: types.RefinementType(types.OneOf(
            types.ModifierType(types.Defaulted(
              types.PrimitiveType(types.String),
              "production",
            )),
            set.from_list(["production", "staging"]),
          )),
          value: value.StringValue("staging"),
        ),
      ],
      Ok("metric{env:staging}"),
    ),
    // Refinement type with Defaulted inner - value NOT provided (uses default)
    #(
      "refinement type with Defaulted inner (None uses default)",
      "metric{$$env->environment$$}",
      [
        helpers.ValueTuple(
          "environment",
          typ: types.RefinementType(types.OneOf(
            types.ModifierType(types.Defaulted(
              types.PrimitiveType(types.String),
              "production",
            )),
            set.from_list(["production", "staging"]),
          )),
          value: value.NilValue,
        ),
      ],
      Ok("metric{env:production}"),
    ),
    // Optional field at end resolves to empty - no hanging comma
    #(
      "optional field at end resolves to empty (no hanging comma)",
      "metric{$$env->environment$$, $$region->region$$}",
      [
        helpers.ValueTuple(
          "environment",
          typ: types.PrimitiveType(types.String),
          value: value.StringValue("production"),
        ),
        helpers.ValueTuple(
          "region",
          typ: types.ModifierType(
            types.Optional(types.PrimitiveType(types.String)),
          ),
          value: value.NilValue,
        ),
      ],
      Ok("metric{env:production}"),
    ),
    // Optional field at start resolves to empty - no hanging comma
    #(
      "optional field at start resolves to empty (no hanging comma)",
      "metric{$$region->region$$, $$env->environment$$}",
      [
        helpers.ValueTuple(
          "region",
          typ: types.ModifierType(
            types.Optional(types.PrimitiveType(types.String)),
          ),
          value: value.NilValue,
        ),
        helpers.ValueTuple(
          "environment",
          typ: types.PrimitiveType(types.String),
          value: value.StringValue("production"),
        ),
      ],
      Ok("metric{env:production}"),
    ),
    // Optional field in middle resolves to empty - no double comma
    #(
      "optional field in middle resolves to empty (no double comma)",
      "metric{$$env->environment$$, $$region->region$$, $$team->team$$}",
      [
        helpers.ValueTuple(
          "environment",
          typ: types.PrimitiveType(types.String),
          value: value.StringValue("production"),
        ),
        helpers.ValueTuple(
          "region",
          typ: types.ModifierType(
            types.Optional(types.PrimitiveType(types.String)),
          ),
          value: value.NilValue,
        ),
        helpers.ValueTuple(
          "team",
          typ: types.PrimitiveType(types.String),
          value: value.StringValue("platform"),
        ),
      ],
      Ok("metric{env:production, team:platform}"),
    ),
    // All optional fields empty - no dangling commas
    #(
      "all optional fields empty (no dangling commas)",
      "metric{$$env->environment$$, $$region->region$$}",
      [
        helpers.ValueTuple(
          "environment",
          typ: types.ModifierType(
            types.Optional(types.PrimitiveType(types.String)),
          ),
          value: value.NilValue,
        ),
        helpers.ValueTuple(
          "region",
          typ: types.ModifierType(
            types.Optional(types.PrimitiveType(types.String)),
          ),
          value: value.NilValue,
        ),
      ],
      Ok("metric{}"),
    ),
    // Optional List field with None value - no hanging comma
    #(
      "optional list field with None value (no hanging comma)",
      "metric{$$env->environment$$, $$tags->tag$$}",
      [
        helpers.ValueTuple(
          "environment",
          typ: types.PrimitiveType(types.String),
          value: value.StringValue("production"),
        ),
        helpers.ValueTuple(
          "tag",
          typ: types.ModifierType(
            types.Optional(
              types.CollectionType(
                types.List(types.PrimitiveType(types.String)),
              ),
            ),
          ),
          value: value.NilValue,
        ),
      ],
      Ok("metric{env:production}"),
    ),
    // Optional with AND operator - empty field at end
    #(
      "optional with AND operator and empty field",
      "metric{$$env->environment$$ AND $$region->region$$}",
      [
        helpers.ValueTuple(
          "environment",
          typ: types.PrimitiveType(types.String),
          value: value.StringValue("production"),
        ),
        helpers.ValueTuple(
          "region",
          typ: types.ModifierType(
            types.Optional(types.PrimitiveType(types.String)),
          ),
          value: value.NilValue,
        ),
      ],
      Ok("metric{env:production}"),
    ),
    // Optional with AND operator - empty field at start
    #(
      "optional with AND operator and empty field at start",
      "metric{$$region->region$$ AND $$env->environment$$}",
      [
        helpers.ValueTuple(
          "region",
          typ: types.ModifierType(
            types.Optional(types.PrimitiveType(types.String)),
          ),
          value: value.NilValue,
        ),
        helpers.ValueTuple(
          "environment",
          typ: types.PrimitiveType(types.String),
          value: value.StringValue("production"),
        ),
      ],
      Ok("metric{env:production}"),
    ),
    // 3 optional fields all empty (multi-pass cleanup)
    #(
      "3 optional fields all empty (multi-pass cleanup)",
      "metric{$$a->a$$, $$b->b$$, $$c->c$$}",
      [
        helpers.ValueTuple(
          "a",
          typ: types.ModifierType(
            types.Optional(types.PrimitiveType(types.String)),
          ),
          value: value.NilValue,
        ),
        helpers.ValueTuple(
          "b",
          typ: types.ModifierType(
            types.Optional(types.PrimitiveType(types.String)),
          ),
          value: value.NilValue,
        ),
        helpers.ValueTuple(
          "c",
          typ: types.ModifierType(
            types.Optional(types.PrimitiveType(types.String)),
          ),
          value: value.NilValue,
        ),
      ],
      Ok("metric{}"),
    ),
    // Optional with Not template type and None value
    #(
      "optional with Not template type and None value",
      "metric{$$env->environment$$ AND $$region->region:not$$}",
      [
        helpers.ValueTuple(
          "environment",
          typ: types.PrimitiveType(types.String),
          value: value.StringValue("production"),
        ),
        helpers.ValueTuple(
          "region",
          typ: types.ModifierType(
            types.Optional(types.PrimitiveType(types.String)),
          ),
          value: value.NilValue,
        ),
      ],
      Ok("metric{env:production}"),
    ),
    // Optional List with Not template type and None value
    #(
      "optional list with Not template type and None value",
      "metric{$$env->environment$$, $$excluded->excluded:not$$}",
      [
        helpers.ValueTuple(
          "environment",
          typ: types.PrimitiveType(types.String),
          value: value.StringValue("production"),
        ),
        helpers.ValueTuple(
          "excluded",
          typ: types.ModifierType(
            types.Optional(
              types.CollectionType(
                types.List(types.PrimitiveType(types.String)),
              ),
            ),
          ),
          value: value.NilValue,
        ),
      ],
      Ok("metric{env:production}"),
    ),
    // Mixed: some Optional fields empty, some provided, with AND operator
    #(
      "mixed some empty some provided with AND operator",
      "metric{$$a->a$$ AND $$b->b$$ AND $$c->c$$ AND $$d->d$$}",
      [
        helpers.ValueTuple(
          "a",
          typ: types.ModifierType(
            types.Optional(types.PrimitiveType(types.String)),
          ),
          value: value.NilValue,
        ),
        helpers.ValueTuple(
          "b",
          typ: types.PrimitiveType(types.String),
          value: value.StringValue("val_b"),
        ),
        helpers.ValueTuple(
          "c",
          typ: types.ModifierType(
            types.Optional(types.PrimitiveType(types.String)),
          ),
          value: value.NilValue,
        ),
        helpers.ValueTuple(
          "d",
          typ: types.PrimitiveType(types.String),
          value: value.StringValue("val_d"),
        ),
      ],
      Ok("metric{b:val_b AND d:val_d}"),
    ),
    // Optional Raw value with None
    #(
      "optional raw value with None",
      "time_slice(query < $$threshold$$ per 10s)",
      [
        helpers.ValueTuple(
          "threshold",
          typ: types.ModifierType(
            types.Optional(
              types.PrimitiveType(types.NumericType(types.Integer)),
            ),
          ),
          value: value.NilValue,
        ),
      ],
      Ok("time_slice(query <  per 10s)"),
    ),
  ]
  |> test_helpers.array_based_test_executor_2(fn(query, value_tuples) {
    templatizer.parse_and_resolve_query_template(
      query,
      value_tuples,
      from: "test",
    )
  })
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
      "parses 'threshold' (no ->) -> Raw",
      "threshold",
      Ok(templatizer.TemplateVariable("threshold", "", templatizer.Raw)),
    ),
    #(
      "parses 'my_value' (no ->) -> Raw",
      "my_value",
      Ok(templatizer.TemplateVariable("my_value", "", templatizer.Raw)),
    ),
    // Datadog format: input->attr
    #(
      "parses 'environment->env' -> Default",
      "bar->foo",
      Ok(templatizer.TemplateVariable("foo", "bar", templatizer.Default)),
    ),
    #(
      "parses 'environment->env:not' -> Not",
      "bar->foo:not",
      Ok(templatizer.TemplateVariable("foo", "bar", templatizer.Not)),
    ),
    // Error cases
    #(
      "rejects empty template name",
      "",
      Error(errors.SemanticAnalysisTemplateParseError(
        msg: "Empty template variable name: ",
        context: errors.empty_context(),
      )),
    ),
    #(
      "rejects whitespace-only template name",
      "  ",
      Error(errors.SemanticAnalysisTemplateParseError(
        msg: "Empty template variable name:   ",
        context: errors.empty_context(),
      )),
    ),
    #(
      "rejects empty input name (with ->)",
      "->foo",
      Error(errors.SemanticAnalysisTemplateParseError(
        msg: "Empty input name in template: ->foo",
        context: errors.empty_context(),
      )),
    ),
    #(
      "rejects empty label name (with ->)",
      "foo->",
      Error(errors.SemanticAnalysisTemplateParseError(
        msg: "Empty label name in template: foo->",
        context: errors.empty_context(),
      )),
    ),
    #(
      "rejects unknown template type",
      "foo->foo:unknown",
      Error(errors.SemanticAnalysisTemplateParseError(
        msg: "Unknown template type: unknown",
        context: errors.empty_context(),
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
    #("not", "not", Ok(templatizer.Not)),
    #(
      "unknown",
      "unknown",
      Error(errors.SemanticAnalysisTemplateParseError(
        msg: "Unknown template type: unknown",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(templatizer.parse_template_type)
}

// ==== Resolve Template ====
// Tests templatizer-specific behavior. Type dispatch is tested in accepted_types_test.
// * ✅ input name and value tuple label don't match
// * ✅ unsupported type - dict (error propagation)
// * ✅ E2E: primitive with Default template type
// * ✅ E2E: list with Not template type
// * ✅ E2E: primitive with Raw template type
pub fn resolve_template_test() {
  [
    // Label mismatch error (templatizer-specific validation)
    #(
      "input name and value tuple label don't match",
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "bar",
        typ: types.PrimitiveType(types.Boolean),
        value: value.BoolValue(True),
      ),
      Error(errors.SemanticAnalysisTemplateResolutionError(
        msg: "Mismatch between template input name (foo) and input value label (bar).",
        context: errors.empty_context(),
      )),
    ),
    // Dict unsupported error (error propagation from type module)
    #(
      "unsupported type - dict (error propagation)",
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: types.CollectionType(types.Dict(
          types.PrimitiveType(types.String),
          types.PrimitiveType(types.Boolean),
        )),
        value: value.DictValue(dict.from_list([])),
      ),
      Error(errors.SemanticAnalysisTemplateResolutionError(
        msg: "Unsupported templatized variable type: Dict(String, Boolean). Dict support is pending, open an issue if this is a desired use case.",
        context: errors.empty_context(),
      )),
    ),
    // E2E: Default template type with string -> "attr:value"
    #(
      "E2E: primitive with Default template type",
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: types.PrimitiveType(types.String),
        value: value.StringValue("bar"),
      ),
      Ok("foo:bar"),
    ),
    // E2E: Not template type with list -> "attr NOT IN (v1, v2)"
    #(
      "E2E: list with Not template type",
      templatizer.TemplateVariable("env", "env", templatizer.Not),
      helpers.ValueTuple(
        label: "env",
        typ: types.CollectionType(types.List(types.PrimitiveType(types.String))),
        value: value.ListValue([
          value.StringValue("dev"),
          value.StringValue("test"),
        ]),
      ),
      Ok("env NOT IN (dev, test)"),
    ),
    // E2E: Raw template type with integer -> just the value
    #(
      "E2E: primitive with Raw template type",
      templatizer.TemplateVariable("count", "", templatizer.Raw),
      helpers.ValueTuple(
        label: "count",
        typ: types.PrimitiveType(types.NumericType(types.Integer)),
        value: value.IntValue(42),
      ),
      Ok("42"),
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
      "Raw: just the value itself",
      templatizer.TemplateVariable("threshold", "", templatizer.Raw),
      "2500000",
      "2500000",
    ),
    #(
      "Default: attr:value (wildcards preserved)",
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      "bar",
      "foo:bar",
    ),
    #(
      "Not: !attr:value (wildcards preserved)",
      templatizer.TemplateVariable("foo", "foo", templatizer.Not),
      "bar",
      "!foo:bar",
    ),
  ]
  |> test_helpers.array_based_test_executor_2(templatizer.resolve_string_value)
}

// ==== Resolve List Value ====
// ==== Non-empty Lists ====
// * ✅ Raw: "v1, v2, v3" (comma-separated)
// * ✅ Default: "attr IN (v1, v2, v3)"
// * ✅ Not: "attr NOT IN (v1, v2)"
// ==== Empty Lists ====
// * ✅ Raw: "v1, v2, v3" (comma-separated)
// * ✅ Default: "attr IN (v1, v2, v3)"
// * ✅ Not: "attr NOT IN (v1, v2)"
pub fn resolve_list_value_test() {
  [
    #(
      "Raw non-empty: comma-separated",
      templatizer.TemplateVariable("values", "", templatizer.Raw),
      ["bar", "baz"],
      "bar, baz",
    ),
    #(
      "Default non-empty: attr IN (v1, v2, v3)",
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      ["bar", "baz"],
      "foo IN (bar, baz)",
    ),
    #(
      "Not non-empty: attr NOT IN (v1, v2)",
      templatizer.TemplateVariable("foo", "foo", templatizer.Not),
      ["bar", "baz"],
      "foo NOT IN (bar, baz)",
    ),
    #(
      "Raw empty: empty string",
      templatizer.TemplateVariable("values", "", templatizer.Raw),
      [],
      "",
    ),
    #(
      "Default empty: empty string",
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      [],
      "",
    ),
    #(
      "Not empty: empty string",
      templatizer.TemplateVariable("foo", "foo", templatizer.Not),
      [],
      "",
    ),
  ]
  |> test_helpers.array_based_test_executor_2(templatizer.resolve_list_value)
}
