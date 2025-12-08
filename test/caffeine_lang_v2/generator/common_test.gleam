import caffeine_lang_v2/common/errors
import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/generator/common
import caffeine_lang_v2/middle_end
import gleam/dict
import gleam/dynamic
import gleam/list
import gleeunit/should

// ==== Helpers ====
fn make_ir(values: List(middle_end.ValueTuple)) -> middle_end.IntermediateRepresentation {
  middle_end.IntermediateRepresentation(
    expectation_name: "test_expectation",
    artifact_ref: "SLO",
    values: values,
  )
}

fn make_value_tuple(
  label: String,
  typ: helpers.AcceptedTypes,
  value: dynamic.Dynamic,
) -> middle_end.ValueTuple {
  middle_end.ValueTuple(label:, typ:, value:)
}

// ==== Tests - get_string_value ====
// * ✅ happy path - string value exists
// * ✅ sad path - key missing
// * ✅ sad path - wrong type
pub fn get_string_value_test() {
  // happy path
  let ir =
    make_ir([make_value_tuple("name", helpers.String, dynamic.string("foo"))])
  common.get_string_value(ir, "name")
  |> should.equal(Ok("foo"))

  // sad paths
  [
    #(make_ir([]), "missing", errors.MissingValue("missing")),
    #(
      make_ir([make_value_tuple("count", helpers.Integer, dynamic.int(42))]),
      "count",
      errors.TypeError("count", "String", "Integer"),
    ),
  ]
  |> list.each(fn(tuple) {
    let #(ir, key, expected_error) = tuple
    common.get_string_value(ir, key)
    |> should.equal(Error(expected_error))
  })
}

// ==== Tests - get_float_value ====
// * ✅ happy path - float value exists
// * ✅ sad path - key missing
// * ✅ sad path - wrong type
pub fn get_float_value_test() {
  // happy path
  let ir =
    make_ir([
      make_value_tuple("threshold", helpers.Float, dynamic.float(99.9)),
    ])
  common.get_float_value(ir, "threshold")
  |> should.equal(Ok(99.9))

  // sad paths
  [
    #(make_ir([]), "missing", errors.MissingValue("missing")),
    #(
      make_ir([make_value_tuple("name", helpers.String, dynamic.string("foo"))]),
      "name",
      errors.TypeError("name", "Float", "String"),
    ),
  ]
  |> list.each(fn(tuple) {
    let #(ir, key, expected_error) = tuple
    common.get_float_value(ir, key)
    |> should.equal(Error(expected_error))
  })
}

// ==== Tests - get_int_value ====
// * ✅ happy path - int value exists
// * ✅ sad path - key missing
// * ✅ sad path - wrong type
pub fn get_int_value_test() {
  // happy path
  let ir =
    make_ir([
      make_value_tuple("window_in_days", helpers.Integer, dynamic.int(30)),
    ])
  common.get_int_value(ir, "window_in_days")
  |> should.equal(Ok(30))

  // sad paths
  [
    #(make_ir([]), "missing", errors.MissingValue("missing")),
    #(
      make_ir([make_value_tuple("name", helpers.String, dynamic.string("foo"))]),
      "name",
      errors.TypeError("name", "Integer", "String"),
    ),
  ]
  |> list.each(fn(tuple) {
    let #(ir, key, expected_error) = tuple
    common.get_int_value(ir, key)
    |> should.equal(Error(expected_error))
  })
}

// ==== Tests - get_string_dict_value ====
// * ✅ happy path - dict value exists
// * ✅ sad path - key missing
// * ✅ sad path - wrong type
pub fn get_string_dict_value_test() {
  // happy path
  let dict_value =
    dynamic.properties([
      #(dynamic.string("numerator"), dynamic.string("query1")),
      #(dynamic.string("denominator"), dynamic.string("query2")),
    ])
  let ir =
    make_ir([
      make_value_tuple(
        "queries",
        helpers.Dict(helpers.String, helpers.String),
        dict_value,
      ),
    ])
  common.get_string_dict_value(ir, "queries")
  |> should.equal(
    Ok(dict.from_list([#("numerator", "query1"), #("denominator", "query2")])),
  )

  // sad paths
  [
    #(make_ir([]), "missing", errors.MissingValue("missing")),
    #(
      make_ir([make_value_tuple("name", helpers.String, dynamic.string("foo"))]),
      "name",
      errors.TypeError("name", "Dict(String, String)", "String"),
    ),
  ]
  |> list.each(fn(tuple) {
    let #(ir, key, expected_error) = tuple
    common.get_string_dict_value(ir, key)
    |> should.equal(Error(expected_error))
  })
}

// ==== Tests - sanitize_resource_name ====
// * ✅ lowercase conversion
// * ✅ special chars replaced with underscore
// * ✅ starts with number gets underscore prefix
// * ✅ valid names unchanged
pub fn sanitize_resource_name_test() {
  [
    #("simple", "simple"),
    #("MixedCase", "mixedcase"),
    #("with spaces", "with_spaces"),
    #("special@chars!", "special_chars_"),
    #("123starts_with_number", "_123starts_with_number"),
    #("valid_name-123", "valid_name-123"),
    #("", "_empty"),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    common.sanitize_resource_name(input)
    |> should.equal(expected)
  })
}

// ==== Tests - days_to_timeframe ====
// * ✅ 7 days
// * ✅ 30 days
// * ✅ 90 days
// * ✅ custom days
pub fn days_to_timeframe_test() {
  [#(7, "7d"), #(30, "30d"), #(90, "90d"), #(14, "14d"), #(60, "60d")]
  |> list.each(fn(pair) {
    let #(days, expected) = pair
    common.days_to_timeframe(days)
    |> should.equal(expected)
  })
}

// ==== Tests - accepted_type_to_string ====
// * ✅ basic types
// * ✅ list types
// * ✅ dict types
pub fn accepted_type_to_string_test() {
  [
    #(helpers.Boolean, "Boolean"),
    #(helpers.Float, "Float"),
    #(helpers.Integer, "Integer"),
    #(helpers.String, "String"),
    #(helpers.List(helpers.String), "List(String)"),
    #(helpers.Dict(helpers.String, helpers.Integer), "Dict(String, Integer)"),
  ]
  |> list.each(fn(pair) {
    let #(typ, expected) = pair
    common.accepted_type_to_string(typ)
    |> should.equal(expected)
  })
}

// ==== Tests - format_error ====
// * ✅ MissingValue
// * ✅ TypeError
// * ✅ InvalidArtifact
// * ✅ RenderError
pub fn format_error_test() {
  [
    #(errors.MissingValue("threshold"), "Missing required value: threshold"),
    #(
      errors.TypeError("count", "Integer", "String"),
      "Type error for 'count': expected Integer, found String",
    ),
    #(errors.InvalidArtifact("Unknown"), "Unknown artifact type: Unknown"),
    #(errors.RenderError("failed to render"), "Render error: failed to render"),
  ]
  |> list.each(fn(pair) {
    let #(error, expected) = pair
    errors.format_generator_error(error)
    |> should.equal(expected)
  })
}
