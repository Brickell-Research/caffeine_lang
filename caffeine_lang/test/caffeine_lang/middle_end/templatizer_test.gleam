import caffeine_lang/common/accepted_types
import caffeine_lang/common/collection_types
import caffeine_lang/common/errors
import caffeine_lang/common/helpers
import caffeine_lang/common/modifier_types
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/common/refinement_types
import caffeine_lang/middle_end/templatizer
import gleam/dynamic
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
pub fn cleanup_empty_template_artifacts_test() {
  [
    // No artifacts - unchanged
    #("metric{env:prod}", "metric{env:prod}"),
    // Trailing comma in braces
    #("metric{env:prod, }", "metric{env:prod}"),
    #("metric{env:prod,}", "metric{env:prod}"),
    // Leading comma in braces
    #("metric{, env:prod}", "metric{env:prod}"),
    #("metric{,env:prod}", "metric{env:prod}"),
    // Trailing comma in parens
    #("tag IN (a, b, )", "tag IN (a, b)"),
    #("tag IN (a, b,)", "tag IN (a, b)"),
    // Leading comma in parens
    #("tag IN (, a, b)", "tag IN (a, b)"),
    #("tag IN (,a, b)", "tag IN (a, b)"),
    // Consecutive commas (middle empty)
    #("metric{env:prod, , team:platform}", "metric{env:prod, team:platform}"),
    #("metric{env:prod,,team:platform}", "metric{env:prod,team:platform}"),
    // AND artifacts
    #("metric{env:prod AND }", "metric{env:prod}"),
    #("metric{ AND env:prod}", "metric{env:prod}"),
    #(
      "metric{env:prod AND  AND team:platform}",
      "metric{env:prod AND team:platform}",
    ),
    // All empty in braces (two optionals)
    #("metric{, }", "metric{}"),
    // All empty in parens (two optionals)
    #("tag IN (, )", "tag IN ()"),
    // Multiple artifacts in one query
    #(
      "avg:my.metric{, env:prod, }.as_count()",
      "avg:my.metric{env:prod}.as_count()",
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
pub fn parse_and_resolve_query_template_test() {
  [
    #(
      "foo.sum$$baz->faz$$",
      [],
      Error(errors.SemanticAnalysisTemplateParseError(
        "test - Missing input for template: faz",
      )),
    ),
    #(
      "foo.sum$$baz",
      [],
      Error(errors.SemanticAnalysisTemplateParseError(
        "test - Unexpected incomplete `$$` for substring: foo.sum$$baz",
      )),
    ),
    #("foo", [], Ok("foo")),
    #(
      "foo.sum{$$foo->bar:not$$ AND $$baz->faz$$}",
      [
        helpers.ValueTuple(
          "bar",
          typ: accepted_types.PrimitiveType(primitive_types.String),
          value: dynamic.string("pizza"),
        ),
        helpers.ValueTuple(
          "faz",
          typ: accepted_types.CollectionType(
            collection_types.List(
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Integer,
              )),
            ),
          ),
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
          typ: accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
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
          typ: accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Float,
          )),
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
          typ: accepted_types.PrimitiveType(primitive_types.String),
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
          typ: accepted_types.PrimitiveType(primitive_types.String),
          value: dynamic.string("production"),
        ),
        helpers.ValueTuple(
          "threshold",
          typ: accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          value: dynamic.int(80),
        ),
      ],
      Ok("time_slice(avg:system.cpu{env:production} > 80 per 300s)"),
    ),
    // Refinement type with Defaulted inner - value provided
    #(
      "metric{$$env->environment$$}",
      [
        helpers.ValueTuple(
          "environment",
          typ: accepted_types.RefinementType(refinement_types.OneOf(
            accepted_types.ModifierType(modifier_types.Defaulted(
              accepted_types.PrimitiveType(primitive_types.String),
              "production",
            )),
            set.from_list(["production", "staging"]),
          )),
          value: dynamic.string("staging"),
        ),
      ],
      Ok("metric{env:staging}"),
    ),
    // Refinement type with Defaulted inner - value NOT provided (uses default)
    #(
      "metric{$$env->environment$$}",
      [
        helpers.ValueTuple(
          "environment",
          typ: accepted_types.RefinementType(refinement_types.OneOf(
            accepted_types.ModifierType(modifier_types.Defaulted(
              accepted_types.PrimitiveType(primitive_types.String),
              "production",
            )),
            set.from_list(["production", "staging"]),
          )),
          value: dynamic.nil(),
        ),
      ],
      Ok("metric{env:production}"),
    ),
    // Optional field at end resolves to empty - no hanging comma
    #(
      "metric{$$env->environment$$, $$region->region$$}",
      [
        helpers.ValueTuple(
          "environment",
          typ: accepted_types.PrimitiveType(primitive_types.String),
          value: dynamic.string("production"),
        ),
        helpers.ValueTuple(
          "region",
          typ: accepted_types.ModifierType(modifier_types.Optional(
            accepted_types.PrimitiveType(primitive_types.String),
          )),
          value: dynamic.nil(),
        ),
      ],
      Ok("metric{env:production}"),
    ),
    // Optional field at start resolves to empty - no hanging comma
    #(
      "metric{$$region->region$$, $$env->environment$$}",
      [
        helpers.ValueTuple(
          "region",
          typ: accepted_types.ModifierType(modifier_types.Optional(
            accepted_types.PrimitiveType(primitive_types.String),
          )),
          value: dynamic.nil(),
        ),
        helpers.ValueTuple(
          "environment",
          typ: accepted_types.PrimitiveType(primitive_types.String),
          value: dynamic.string("production"),
        ),
      ],
      Ok("metric{env:production}"),
    ),
    // Optional field in middle resolves to empty - no double comma
    #(
      "metric{$$env->environment$$, $$region->region$$, $$team->team$$}",
      [
        helpers.ValueTuple(
          "environment",
          typ: accepted_types.PrimitiveType(primitive_types.String),
          value: dynamic.string("production"),
        ),
        helpers.ValueTuple(
          "region",
          typ: accepted_types.ModifierType(modifier_types.Optional(
            accepted_types.PrimitiveType(primitive_types.String),
          )),
          value: dynamic.nil(),
        ),
        helpers.ValueTuple(
          "team",
          typ: accepted_types.PrimitiveType(primitive_types.String),
          value: dynamic.string("platform"),
        ),
      ],
      Ok("metric{env:production, team:platform}"),
    ),
    // All optional fields empty - no dangling commas
    #(
      "metric{$$env->environment$$, $$region->region$$}",
      [
        helpers.ValueTuple(
          "environment",
          typ: accepted_types.ModifierType(modifier_types.Optional(
            accepted_types.PrimitiveType(primitive_types.String),
          )),
          value: dynamic.nil(),
        ),
        helpers.ValueTuple(
          "region",
          typ: accepted_types.ModifierType(modifier_types.Optional(
            accepted_types.PrimitiveType(primitive_types.String),
          )),
          value: dynamic.nil(),
        ),
      ],
      Ok("metric{}"),
    ),
    // Optional List field with None value - no hanging comma
    #(
      "metric{$$env->environment$$, $$tags->tag$$}",
      [
        helpers.ValueTuple(
          "environment",
          typ: accepted_types.PrimitiveType(primitive_types.String),
          value: dynamic.string("production"),
        ),
        helpers.ValueTuple(
          "tag",
          typ: accepted_types.ModifierType(modifier_types.Optional(
            accepted_types.CollectionType(
              collection_types.List(
                accepted_types.PrimitiveType(primitive_types.String),
              ),
            ),
          )),
          value: dynamic.nil(),
        ),
      ],
      Ok("metric{env:production}"),
    ),
    // Optional with AND operator - empty field at end
    #(
      "metric{$$env->environment$$ AND $$region->region$$}",
      [
        helpers.ValueTuple(
          "environment",
          typ: accepted_types.PrimitiveType(primitive_types.String),
          value: dynamic.string("production"),
        ),
        helpers.ValueTuple(
          "region",
          typ: accepted_types.ModifierType(modifier_types.Optional(
            accepted_types.PrimitiveType(primitive_types.String),
          )),
          value: dynamic.nil(),
        ),
      ],
      Ok("metric{env:production}"),
    ),
    // Optional with AND operator - empty field at start
    #(
      "metric{$$region->region$$ AND $$env->environment$$}",
      [
        helpers.ValueTuple(
          "region",
          typ: accepted_types.ModifierType(modifier_types.Optional(
            accepted_types.PrimitiveType(primitive_types.String),
          )),
          value: dynamic.nil(),
        ),
        helpers.ValueTuple(
          "environment",
          typ: accepted_types.PrimitiveType(primitive_types.String),
          value: dynamic.string("production"),
        ),
      ],
      Ok("metric{env:production}"),
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
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "bar",
        typ: accepted_types.PrimitiveType(primitive_types.Boolean),
        value: dynamic.bool(True),
      ),
      Error(errors.SemanticAnalysisTemplateResolutionError(
        "Mismatch between template input name (foo) and input value label (bar).",
      )),
    ),
    // Dict unsupported error (error propagation from type module)
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: accepted_types.CollectionType(collection_types.Dict(
          accepted_types.PrimitiveType(primitive_types.String),
          accepted_types.PrimitiveType(primitive_types.Boolean),
        )),
        value: dynamic.array([]),
      ),
      Error(errors.SemanticAnalysisTemplateResolutionError(
        "Unsupported templatized variable type: Dict(String, Boolean). Dict support is pending, open an issue if this is a desired use case.",
      )),
    ),
    // E2E: Default template type with string -> "attr:value"
    #(
      templatizer.TemplateVariable("foo", "foo", templatizer.Default),
      helpers.ValueTuple(
        label: "foo",
        typ: accepted_types.PrimitiveType(primitive_types.String),
        value: dynamic.string("bar"),
      ),
      Ok("foo:bar"),
    ),
    // E2E: Not template type with list -> "attr NOT IN (v1, v2)"
    #(
      templatizer.TemplateVariable("env", "env", templatizer.Not),
      helpers.ValueTuple(
        label: "env",
        typ: accepted_types.CollectionType(
          collection_types.List(accepted_types.PrimitiveType(
            primitive_types.String,
          )),
        ),
        value: dynamic.list([dynamic.string("dev"), dynamic.string("test")]),
      ),
      Ok("env NOT IN (dev, test)"),
    ),
    // E2E: Raw template type with integer -> just the value
    #(
      templatizer.TemplateVariable("count", "", templatizer.Raw),
      helpers.ValueTuple(
        label: "count",
        typ: accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        value: dynamic.int(42),
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
    #(templatizer.TemplateVariable("values", "", templatizer.Raw), [], ""),
    #(templatizer.TemplateVariable("foo", "foo", templatizer.Default), [], ""),
    #(templatizer.TemplateVariable("foo", "foo", templatizer.Not), [], ""),
  ]
  |> test_helpers.array_based_test_executor_2(templatizer.resolve_list_value)
}
