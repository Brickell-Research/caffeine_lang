import caffeine_lang/common/errors
import caffeine_lang/common/helpers
import caffeine_lang/common/validations
import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/string
import gleeunit/should
import test_helpers

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
// Optional types
// * (✅, ✅) Optional(String) with value
// * (✅, ✅) Optional(Integer) with value
// * (✅, ✅) Optional(Float) with value
// * (✅, ✅) Optional(Boolean) with value
// * (✅, ✅) Optional(List(String)) with value
// * (✅, ✅) Optional(Dict(String, String)) with value
// Defaulted types
// * (✅, ✅) Defaulted(String, default) with value
// * (✅, ✅) Defaulted(Integer, default) with value
// * (✅, ✅) Defaulted(Float, default) with value
// * (✅, ✅) Defaulted(Boolean, default) with value
// * (✅, ✅) Defaulted(List(String), default) with value
// * (✅, ✅) Defaulted(Dict(String, String), default) with value
// Nested types
// * (✅, ✅) List(List(String))
// * (✅, ✅) Dict(String, Dict(String, Integer))
// * (✅, ✅) List(Dict(String, String))
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
  let dict_string_string = dynamic.properties([#(some_string, other_string)])
  let dict_string_int = dynamic.properties([#(some_string, dynamic.int(1))])
  let dict_string_float =
    dynamic.properties([#(some_string, dynamic.float(1.5))])
  let dict_string_bool = dynamic.properties([#(some_string, some_bool)])
  let list_string = dynamic.list([some_string, other_string])
  let list_int = dynamic.list([dynamic.int(1), dynamic.int(2)])
  let list_bool = dynamic.list([some_bool, some_bool])
  let list_float = dynamic.list([dynamic.float(1.1), dynamic.float(2.2)])
  let empty_list = dynamic.list([])
  let empty_dict = dynamic.properties([])

  [
    // Basic types
    #(some_bool, helpers.Boolean, Ok(some_bool)),
    #(some_int, helpers.Integer, Ok(some_int)),
    #(some_float, helpers.Float, Ok(some_float)),
    #(some_string, helpers.String, Ok(some_string)),
    // Dict types
    #(
      dict_string_string,
      helpers.Dict(helpers.String, helpers.String),
      Ok(dict_string_string),
    ),
    #(
      dict_string_int,
      helpers.Dict(helpers.String, helpers.Integer),
      Ok(dict_string_int),
    ),
    #(
      dict_string_float,
      helpers.Dict(helpers.String, helpers.Float),
      Ok(dict_string_float),
    ),
    #(
      dict_string_bool,
      helpers.Dict(helpers.String, helpers.Boolean),
      Ok(dict_string_bool),
    ),
    // List types
    #(list_string, helpers.List(helpers.String), Ok(list_string)),
    #(list_int, helpers.List(helpers.Integer), Ok(list_int)),
    #(list_bool, helpers.List(helpers.Boolean), Ok(list_bool)),
    #(list_float, helpers.List(helpers.Float), Ok(list_float)),
    // Empty collections
    #(empty_list, helpers.List(helpers.String), Ok(empty_list)),
    #(
      empty_dict,
      helpers.Dict(helpers.String, helpers.String),
      Ok(empty_dict),
    ),
    // Optional types with values
    #(some_string, helpers.Optional(helpers.String), Ok(some_string)),
    #(some_int, helpers.Optional(helpers.Integer), Ok(some_int)),
    #(some_float, helpers.Optional(helpers.Float), Ok(some_float)),
    #(some_bool, helpers.Optional(helpers.Boolean), Ok(some_bool)),
    // Optional List types
    #(
      list_string,
      helpers.Optional(helpers.List(helpers.String)),
      Ok(list_string),
    ),
    // Optional Dict types
    #(
      dict_string_string,
      helpers.Optional(helpers.Dict(helpers.String, helpers.String)),
      Ok(dict_string_string),
    ),
    // Defaulted types with values
    #(
      some_string,
      helpers.Defaulted(helpers.String, "default"),
      Ok(some_string),
    ),
    #(some_int, helpers.Defaulted(helpers.Integer, "0"), Ok(some_int)),
    #(some_float, helpers.Defaulted(helpers.Float, "0.0"), Ok(some_float)),
    #(some_bool, helpers.Defaulted(helpers.Boolean, "False"), Ok(some_bool)),
    // Defaulted List types
    #(
      list_string,
      helpers.Defaulted(helpers.List(helpers.String), ""),
      Ok(list_string),
    ),
    // Defaulted Dict types
    #(
      dict_string_string,
      helpers.Defaulted(helpers.Dict(helpers.String, helpers.String), ""),
      Ok(dict_string_string),
    ),
    // Nested types
    #(
      dynamic.list([list_string, list_string]),
      helpers.List(helpers.List(helpers.String)),
      Ok(dynamic.list([list_string, list_string])),
    ),
    #(
      dynamic.properties([#(some_string, dict_string_int)]),
      helpers.Dict(helpers.String, helpers.Dict(helpers.String, helpers.Integer)),
      Ok(dynamic.properties([#(some_string, dict_string_int)])),
    ),
    #(
      dynamic.list([dict_string_string]),
      helpers.List(helpers.Dict(helpers.String, helpers.String)),
      Ok(dynamic.list([dict_string_string])),
    ),
  ]
  |> test_helpers.array_based_test_executor_2(fn(value, expected_type) {
    validations.validate_value_type(value, expected_type, "")
  })

  // sad paths
  let json_error = fn(msg) { Error(errors.ParserJsonParserError(msg)) }

  [
    // Basic types
    #(
      some_string,
      helpers.Boolean,
      json_error("expected (Bool) received (String) for (some_key)"),
    ),
    #(
      some_string,
      helpers.Integer,
      json_error("expected (Int) received (String) for (some_key)"),
    ),
    #(
      some_string,
      helpers.Float,
      json_error("expected (Float) received (String) for (some_key)"),
    ),
    #(
      some_bool,
      helpers.String,
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    // Dict types
    #(
      dynamic.properties([#(some_string, some_bool)]),
      helpers.Dict(helpers.String, helpers.String),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    #(
      dynamic.properties([#(some_string, some_bool)]),
      helpers.Dict(helpers.String, helpers.Integer),
      json_error("expected (Int) received (Bool) for (some_key)"),
    ),
    #(
      dynamic.properties([#(some_string, some_bool)]),
      helpers.Dict(helpers.String, helpers.Float),
      json_error("expected (Float) received (Bool) for (some_key)"),
    ),
    #(
      dynamic.properties([#(some_string, some_string)]),
      helpers.Dict(helpers.String, helpers.Boolean),
      json_error("expected (Bool) received (String) for (some_key)"),
    ),
    // List types
    #(
      dynamic.list([some_string, some_bool]),
      helpers.List(helpers.String),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    #(
      dynamic.list([dynamic.int(1), some_bool]),
      helpers.List(helpers.Integer),
      json_error("expected (Int) received (Bool) for (some_key)"),
    ),
    #(
      dynamic.list([some_bool, some_string]),
      helpers.List(helpers.Boolean),
      json_error("expected (Bool) received (String) for (some_key)"),
    ),
    #(
      dynamic.list([dynamic.float(1.1), some_bool]),
      helpers.List(helpers.Float),
      json_error("expected (Float) received (Bool) for (some_key)"),
    ),
    // Wrong structure types
    #(
      some_string,
      helpers.List(helpers.String),
      json_error("expected (List) received (String) for (some_key)"),
    ),
    #(
      some_string,
      helpers.Dict(helpers.String, helpers.String),
      json_error("expected (Dict) received (String) for (some_key)"),
    ),
    // Multi-entry collection with one bad value
    #(
      dynamic.properties([
        #(some_string, other_string),
        #(dynamic.string("key2"), some_bool),
      ]),
      helpers.Dict(helpers.String, helpers.String),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    // List with first element wrong
    #(
      dynamic.list([some_bool, some_string]),
      helpers.List(helpers.String),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    // Optional types with wrong inner type
    #(
      some_bool,
      helpers.Optional(helpers.String),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    #(
      some_string,
      helpers.Optional(helpers.Integer),
      json_error("expected (Int) received (String) for (some_key)"),
    ),
    // Optional List with wrong inner type
    #(
      dynamic.list([some_bool]),
      helpers.Optional(helpers.List(helpers.String)),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    // Optional Dict with wrong value type
    #(
      dynamic.properties([#(some_string, some_bool)]),
      helpers.Optional(helpers.Dict(helpers.String, helpers.String)),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    // Defaulted types with wrong inner type
    #(
      some_bool,
      helpers.Defaulted(helpers.String, "default"),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    #(
      some_string,
      helpers.Defaulted(helpers.Integer, "0"),
      json_error("expected (Int) received (String) for (some_key)"),
    ),
    // Defaulted List with wrong inner type
    #(
      dynamic.list([some_bool]),
      helpers.Defaulted(helpers.List(helpers.String), ""),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    // Defaulted Dict with wrong value type
    #(
      dynamic.properties([#(some_string, some_bool)]),
      helpers.Defaulted(helpers.Dict(helpers.String, helpers.String), ""),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    // Nested types with wrong inner type
    #(
      dynamic.list([dynamic.list([some_bool])]),
      helpers.List(helpers.List(helpers.String)),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    #(
      dynamic.properties([#(some_string, dynamic.properties([#(some_string, some_bool)]))]),
      helpers.Dict(helpers.String, helpers.Dict(helpers.String, helpers.String)),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    #(
      dynamic.list([dynamic.properties([#(some_string, some_bool)])]),
      helpers.List(helpers.Dict(helpers.String, helpers.String)),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
  ]
  |> test_helpers.array_based_test_executor_2(fn(value, expected_type) {
    validations.validate_value_type(value, expected_type, "some_key")
  })
}

// ==== Inputs Validator ====
// * ✅ happy path - no inputs
// * ✅ happy path - some inputs
// * ✅ happy path - optional param omitted
// * ✅ happy path - optional param provided
// * ✅ happy path - mix of required and optional, optional omitted
// * ✅ happy path - defaulted param omitted
// * ✅ happy path - defaulted param provided
// * ✅ happy path - mix of required and defaulted, defaulted omitted
// * ✅ missing inputs for params (single)
// * ✅ missing inputs for params (multiple)
// * ✅ extra inputs
// * ✅ missing and extra inputs
// * ✅ type validation error - single
// * ✅ type validation error - multiple
// * ✅ missing required when optional exists
// * ✅ missing required when defaulted exists
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
    // optional param omitted - should pass
    #(
      dict.from_list([#("maybe_name", helpers.Optional(helpers.String))]),
      dict.from_list([]),
    ),
    // optional param provided - should pass
    #(
      dict.from_list([#("maybe_name", helpers.Optional(helpers.String))]),
      dict.from_list([#("maybe_name", dynamic.string("foo"))]),
    ),
    // mix of required and optional, optional omitted - should pass
    #(
      dict.from_list([
        #("name", helpers.String),
        #("maybe_count", helpers.Optional(helpers.Integer)),
      ]),
      dict.from_list([#("name", dynamic.string("foo"))]),
    ),
    // defaulted param omitted - should pass
    #(
      dict.from_list([#("count", helpers.Defaulted(helpers.Integer, "10"))]),
      dict.from_list([]),
    ),
    // defaulted param provided - should pass
    #(
      dict.from_list([#("count", helpers.Defaulted(helpers.Integer, "10"))]),
      dict.from_list([#("count", dynamic.int(42))]),
    ),
    // mix of required and defaulted, defaulted omitted - should pass
    #(
      dict.from_list([
        #("name", helpers.String),
        #("count", helpers.Defaulted(helpers.Integer, "10")),
      ]),
      dict.from_list([#("name", dynamic.string("foo"))]),
    ),
  ]
  |> list.each(fn(pair) {
    let #(params, inputs) = pair
    validations.inputs_validator(params:, inputs:)
    |> should.equal(Ok(True))
  })

  // sad paths
  [
    // missing inputs for params (single)
    #(
      dict.from_list([#("name", helpers.String), #("count", helpers.Integer)]),
      dict.from_list([#("name", dynamic.string("foo"))]),
      Error("Missing keys in input: count"),
    ),
    // extra inputs
    #(
      dict.from_list([#("name", helpers.String)]),
      dict.from_list([
        #("name", dynamic.string("foo")),
        #("extra", dynamic.int(42)),
      ]),
      Error("Extra keys in input: extra"),
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
      Error("Extra keys in input: extra and missing keys in input: required"),
    ),
    // type validation error - single
    #(
      dict.from_list([#("count", helpers.Integer)]),
      dict.from_list([#("count", dynamic.string("not an int"))]),
      Error("expected (Int) received (String) for (count)"),
    ),
    // missing required when optional param exists - should fail for required only
    #(
      dict.from_list([
        #("name", helpers.String),
        #("maybe_count", helpers.Optional(helpers.Integer)),
      ]),
      dict.from_list([]),
      Error("Missing keys in input: name"),
    ),
    // missing required when defaulted param exists - should fail for required only
    #(
      dict.from_list([
        #("name", helpers.String),
        #("count", helpers.Defaulted(helpers.Integer, "10")),
      ]),
      dict.from_list([]),
      Error("Missing keys in input: name"),
    ),
  ]
  |> test_helpers.array_based_test_executor_2(fn(params, inputs) {
    validations.inputs_validator(params:, inputs:)
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
    let result = validations.inputs_validator(params:, inputs:)
    result |> should.be_error
    let assert Error(msg) = result
    string.contains(msg, expected_substring) |> should.be_true
  })
}

// ==== Validate Relevant Uniqueness Tests ====
// * ✅ happy path - no things to validate
// * ✅ happy path - multiple things to validate
// * ✅ sad path - one non-unique
// * ✅ sad path - multiple non-unique
pub fn validate_relevant_uniqueness_test() {
  let fetch_name = fn(thing: #(String, Int)) { thing.0 }

  // happy paths
  [
    #([], Ok(True)),
    #([#("alice", 1), #("bob", 2), #("charlie", 3)], Ok(True)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(things) {
    validations.validate_relevant_uniqueness(things, fetch_name, "names")
  })

  // sad paths - exact match
  [
    #(
      [#("alice", 1), #("alice", 2)],
      Error(errors.ParserDuplicateError("Duplicate names: alice")),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(things) {
    validations.validate_relevant_uniqueness(things, fetch_name, "names")
  })

  // sad paths - order not guaranteed (check contains)
  [
    #(
      [#("alice", 1), #("bob", 2), #("alice", 3), #("bob", 4), #("chad", 5)],
      "Duplicate names: ",
    ),
  ]
  |> list.each(fn(pair) {
    let #(things, expected_substring) = pair
    let result =
      validations.validate_relevant_uniqueness(things, fetch_name, "names")
    result |> should.be_error
    let assert Error(errors.ParserDuplicateError(msg)) = result
    string.contains(msg, expected_substring) |> should.be_true
  })
}

// ==== Validate Inputs For Collection Tests ====
// * ✅ happy path - empty collection
// * ✅ happy path - valid inputs
// * ✅ sad path - invalid inputs
pub fn validate_inputs_for_collection_test() {
  // happy paths
  [
    [],
    [
      #(
        dict.from_list([#("name", dynamic.string("foo"))]),
        dict.from_list([#("name", helpers.String)]),
      ),
    ],
  ]
  |> list.each(fn(collection) {
    validations.validate_inputs_for_collection(collection, fn(p) { p }, fn(p) {
      p
    })
    |> should.equal(Ok(True))
  })

  // sad path
  let collection = [
    #(
      dict.from_list([#("count", dynamic.string("not an int"))]),
      dict.from_list([#("count", helpers.Integer)]),
    ),
  ]
  validations.validate_inputs_for_collection(collection, fn(p) { p }, fn(p) {
    p
  })
  |> should.be_error
}

// ==== Check Collection Key Overshadowing Tests ====
// * ✅ happy path - both collections empty
// * ✅ happy path - no overlapping keys
// * ✅ sad path - single overlapping key
// * ✅ sad path - multiple overlapping keys
pub fn check_collection_key_overshadowing_test() {
  let error_prefix = "Overshadowing keys: "

  // happy paths
  [
    #(dict.new(), dict.new()),
    #(
      dict.from_list([#("alice", 1), #("bob", 2)]),
      dict.from_list([#("charlie", 3), #("dave", 4)]),
    ),
  ]
  |> list.each(fn(pair) {
    let #(reference, referrer) = pair
    validations.check_collection_key_overshadowing(
      reference,
      referrer,
      error_prefix,
    )
    |> should.equal(Ok(True))
  })

  // sad paths
  [
    #(
      dict.from_list([#("alice", 1), #("bob", 2)]),
      dict.from_list([#("alice", 3)]),
      "alice",
    ),
    #(
      dict.from_list([#("alice", 1), #("bob", 2), #("charlie", 3)]),
      dict.from_list([#("alice", 10), #("bob", 20)]),
      "",
    ),
  ]
  |> list.each(fn(tuple) {
    let #(reference, referrer, _expected_substring) = tuple
    let result =
      validations.check_collection_key_overshadowing(
        reference,
        referrer,
        error_prefix,
      )
    result |> should.be_error
  })
}
