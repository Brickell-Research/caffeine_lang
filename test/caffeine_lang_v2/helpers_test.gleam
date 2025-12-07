import caffeine_lang_v2/common/helpers
import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/string
import gleeunit/should

// ==== Validate Types ====
// (happy, sad)
// Basic types
// * (✅, ✅) Boolean
// * (✅, ✅) Float
// * (✅, ✅) Integer
// * (✅, ✅) String
// Dict types
// * (✅, ✅) Dict(String, String)
// * (✅, ✅) Dict(String, Integer)
// * (✅, ✅) Dict(String, Float)
// * (✅, ✅) Dict(String, Boolean)
// * (✅, ✅) Empty Dict
// List types
// * (✅, ✅) List(String)
// * (✅, ✅) List(Integer)
// * (✅, ✅) List(Boolean)
// * (✅, ✅) List(Float)
// * (✅, ✅) Empty List
// Other
// * (n/a, ✅) Wrong structure (string for List/Dict)
// * (n/a, ✅) Multi-entry collection with one bad value
// * (n/a, ✅) List with first element wrong
pub fn validate_value_type_test() {
  let some_string = dynamic.string("a")
  let other_string = dynamic.string("b")
  let some_int = dynamic.int(10)
  let some_float = dynamic.float(11.7)
  let some_bool = dynamic.bool(True)

  // happy paths
  [
    // Basic types
    #(some_bool, helpers.Boolean),
    #(some_int, helpers.Integer),
    #(some_float, helpers.Float),
    #(some_string, helpers.String),
    // Dict types
    #(
      dynamic.properties([#(some_string, other_string)]),
      helpers.Dict(helpers.String, helpers.String),
    ),
    #(
      dynamic.properties([#(some_string, dynamic.int(1))]),
      helpers.Dict(helpers.String, helpers.Integer),
    ),
    #(
      dynamic.properties([#(some_string, dynamic.float(1.5))]),
      helpers.Dict(helpers.String, helpers.Float),
    ),
    #(
      dynamic.properties([#(some_string, some_bool)]),
      helpers.Dict(helpers.String, helpers.Boolean),
    ),
    // List types
    #(dynamic.list([some_string, other_string]), helpers.List(helpers.String)),
    #(
      dynamic.list([dynamic.int(1), dynamic.int(2)]),
      helpers.List(helpers.Integer),
    ),
    #(dynamic.list([some_bool, some_bool]), helpers.List(helpers.Boolean)),
    #(
      dynamic.list([dynamic.float(1.1), dynamic.float(2.2)]),
      helpers.List(helpers.Float),
    ),
    // Empty collections
    #(dynamic.list([]), helpers.List(helpers.String)),
    #(dynamic.properties([]), helpers.Dict(helpers.String, helpers.String)),
  ]
  |> list.each(fn(pair) {
    let #(value, expected_type) = pair
    helpers.validate_value_type(value, expected_type, "")
    |> should.be_ok
  })

  // sad paths
  [
    // Basic types
    #(
      some_string,
      helpers.Boolean,
      "expected (Bool) received (String) for (some_key)",
    ),
    #(
      some_string,
      helpers.Integer,
      "expected (Int) received (String) for (some_key)",
    ),
    #(
      some_string,
      helpers.Float,
      "expected (Float) received (String) for (some_key)",
    ),
    #(
      some_bool,
      helpers.String,
      "expected (String) received (Bool) for (some_key)",
    ),
    // Dict types
    #(
      dynamic.properties([#(some_string, some_bool)]),
      helpers.Dict(helpers.String, helpers.String),
      "expected (String) received (Bool) for (some_key)",
    ),
    #(
      dynamic.properties([#(some_string, some_bool)]),
      helpers.Dict(helpers.String, helpers.Integer),
      "expected (Int) received (Bool) for (some_key)",
    ),
    #(
      dynamic.properties([#(some_string, some_bool)]),
      helpers.Dict(helpers.String, helpers.Float),
      "expected (Float) received (Bool) for (some_key)",
    ),
    #(
      dynamic.properties([#(some_string, some_string)]),
      helpers.Dict(helpers.String, helpers.Boolean),
      "expected (Bool) received (String) for (some_key)",
    ),
    // List types
    #(
      dynamic.list([some_string, some_bool]),
      helpers.List(helpers.String),
      "expected (String) received (Bool) for (some_key)",
    ),
    #(
      dynamic.list([dynamic.int(1), some_bool]),
      helpers.List(helpers.Integer),
      "expected (Int) received (Bool) for (some_key)",
    ),
    #(
      dynamic.list([some_bool, some_string]),
      helpers.List(helpers.Boolean),
      "expected (Bool) received (String) for (some_key)",
    ),
    #(
      dynamic.list([dynamic.float(1.1), some_bool]),
      helpers.List(helpers.Float),
      "expected (Float) received (Bool) for (some_key)",
    ),
    // Wrong structure types
    #(
      some_string,
      helpers.List(helpers.String),
      "expected (List) received (String) for (some_key)",
    ),
    #(
      some_string,
      helpers.Dict(helpers.String, helpers.String),
      "expected (Dict) received (String) for (some_key)",
    ),
    // Multi-entry collection with one bad value
    #(
      dynamic.properties([
        #(some_string, other_string),
        #(dynamic.string("key2"), some_bool),
      ]),
      helpers.Dict(helpers.String, helpers.String),
      "expected (String) received (Bool) for (some_key)",
    ),
    // List with first element wrong
    #(
      dynamic.list([some_bool, some_string]),
      helpers.List(helpers.String),
      "expected (String) received (Bool) for (some_key)",
    ),
  ]
  |> list.each(fn(tuple) {
    let #(value, expected_type, msg) = tuple
    helpers.validate_value_type(value, expected_type, "some_key")
    |> should.equal(Error(helpers.JsonParserError(msg)))
  })
}

// ==== Inputs Validator ====
// * ✅ happy path - no inputs
// * ✅ happy path - some inputs
// * ✅ missing inputs for params (single)
// * ✅ missing inputs for params (multiple)
// * ✅ extra inputs
// * ✅ missing and extra inputs
// * ✅ type validation error - single
// * ✅ type validation error - multiple
pub fn inputs_validator_test() {
  // happy paths
  [
    // no inputs
    #(dict.new(), dict.new()),
    // some inputs
    #(
      dict.from_list([#("name", helpers.String), #("count", helpers.Integer)]),
      dict.from_list([
        #("name", dynamic.string("foo")),
        #("count", dynamic.int(42)),
      ]),
    ),
  ]
  |> list.each(fn(pair) {
    let #(params, inputs) = pair
    helpers.inputs_validator(params:, inputs:)
    |> should.equal(Ok(True))
  })

  // sad paths
  [
    // missing inputs for params (single)
    #(
      dict.from_list([#("name", helpers.String), #("count", helpers.Integer)]),
      dict.from_list([#("name", dynamic.string("foo"))]),
      "Missing keys in input: count",
    ),
    // extra inputs
    #(
      dict.from_list([#("name", helpers.String)]),
      dict.from_list([
        #("name", dynamic.string("foo")),
        #("extra", dynamic.int(42)),
      ]),
      "Extra keys in input: extra",
    ),
    // missing and extra inputs
    #(
      dict.from_list([
        #("name", helpers.String),
        #("required", helpers.Boolean),
      ]),
      dict.from_list([
        #("name", dynamic.string("foo")),
        #("extra", dynamic.int(42)),
      ]),
      "Extra keys in input: extra and missing keys in input: required",
    ),
    // type validation error - single
    #(
      dict.from_list([#("count", helpers.Integer)]),
      dict.from_list([#("count", dynamic.string("not an int"))]),
      "expected (Int) received (String) for (count)",
    ),
  ]
  |> list.each(fn(tuple) {
    let #(params, inputs, expected_msg) = tuple
    helpers.inputs_validator(params:, inputs:)
    |> should.equal(Error(expected_msg))
  })

  // sad paths - error exists but order not guaranteed (check contains)
  [
    // missing inputs for params (multiple)
    #(
      dict.from_list([
        #("name", helpers.String),
        #("count", helpers.Integer),
        #("flag", helpers.Boolean),
      ]),
      dict.from_list([#("name", dynamic.string("foo"))]),
      "Missing keys in input:",
    ),
    // type validation error - multiple
    #(
      dict.from_list([#("count", helpers.Integer), #("flag", helpers.Boolean)]),
      dict.from_list([
        #("count", dynamic.string("not an int")),
        #("flag", dynamic.string("not a bool")),
      ]),
      "expected (Int) received (String)",
    ),
  ]
  |> list.each(fn(tuple) {
    let #(params, inputs, expected_substring) = tuple
    let result = helpers.inputs_validator(params:, inputs:)
    result |> should.be_error
    let assert Error(msg) = result
    string.contains(msg, expected_substring) |> should.be_true
  })
}
