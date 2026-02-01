import caffeine_lang/errors
import caffeine_lang/linker/validations
import caffeine_lang/types
import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/set
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
// Defaulted types (only primitives allowed)
// * (✅, ✅) Defaulted(String, default) with value
// * (✅, ✅) Defaulted(Integer, default) with value
// * (✅, ✅) Defaulted(Float, default) with value
// * (✅, ✅) Defaulted(Boolean, default) with value
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
    #(some_bool, types.PrimitiveType(types.Boolean), Ok(some_bool)),
    #(
      some_int,
      types.PrimitiveType(types.NumericType(types.Integer)),
      Ok(some_int),
    ),
    #(
      some_float,
      types.PrimitiveType(types.NumericType(types.Float)),
      Ok(some_float),
    ),
    #(some_string, types.PrimitiveType(types.String), Ok(some_string)),
    // Dict types
    #(
      dict_string_string,
      types.CollectionType(types.Dict(
        types.PrimitiveType(types.String),
        types.PrimitiveType(types.String),
      )),
      Ok(dict_string_string),
    ),
    #(
      dict_string_int,
      types.CollectionType(types.Dict(
        types.PrimitiveType(types.String),
        types.PrimitiveType(types.NumericType(types.Integer)),
      )),
      Ok(dict_string_int),
    ),
    #(
      dict_string_float,
      types.CollectionType(types.Dict(
        types.PrimitiveType(types.String),
        types.PrimitiveType(types.NumericType(types.Float)),
      )),
      Ok(dict_string_float),
    ),
    #(
      dict_string_bool,
      types.CollectionType(types.Dict(
        types.PrimitiveType(types.String),
        types.PrimitiveType(types.Boolean),
      )),
      Ok(dict_string_bool),
    ),
    // List types
    #(
      list_string,
      types.CollectionType(types.List(types.PrimitiveType(types.String))),
      Ok(list_string),
    ),
    #(
      list_int,
      types.CollectionType(
        types.List(types.PrimitiveType(types.NumericType(types.Integer))),
      ),
      Ok(list_int),
    ),
    #(
      list_bool,
      types.CollectionType(types.List(types.PrimitiveType(types.Boolean))),
      Ok(list_bool),
    ),
    #(
      list_float,
      types.CollectionType(
        types.List(types.PrimitiveType(types.NumericType(types.Float))),
      ),
      Ok(list_float),
    ),
    // Empty collections
    #(
      empty_list,
      types.CollectionType(types.List(types.PrimitiveType(types.String))),
      Ok(empty_list),
    ),
    #(
      empty_dict,
      types.CollectionType(types.Dict(
        types.PrimitiveType(types.String),
        types.PrimitiveType(types.String),
      )),
      Ok(empty_dict),
    ),
    // Optional types with values
    #(
      some_string,
      types.ModifierType(types.Optional(types.PrimitiveType(types.String))),
      Ok(some_string),
    ),
    #(
      some_int,
      types.ModifierType(
        types.Optional(types.PrimitiveType(types.NumericType(types.Integer))),
      ),
      Ok(some_int),
    ),
    #(
      some_float,
      types.ModifierType(
        types.Optional(types.PrimitiveType(types.NumericType(types.Float))),
      ),
      Ok(some_float),
    ),
    #(
      some_bool,
      types.ModifierType(types.Optional(types.PrimitiveType(types.Boolean))),
      Ok(some_bool),
    ),
    // Optional List types
    #(
      list_string,
      types.ModifierType(
        types.Optional(
          types.CollectionType(types.List(types.PrimitiveType(types.String))),
        ),
      ),
      Ok(list_string),
    ),
    // Optional Dict types
    #(
      dict_string_string,
      types.ModifierType(
        types.Optional(
          types.CollectionType(types.Dict(
            types.PrimitiveType(types.String),
            types.PrimitiveType(types.String),
          )),
        ),
      ),
      Ok(dict_string_string),
    ),
    // Defaulted types with values
    #(
      some_string,
      types.ModifierType(types.Defaulted(
        types.PrimitiveType(types.String),
        "default",
      )),
      Ok(some_string),
    ),
    #(
      some_int,
      types.ModifierType(types.Defaulted(
        types.PrimitiveType(types.NumericType(types.Integer)),
        "0",
      )),
      Ok(some_int),
    ),
    #(
      some_float,
      types.ModifierType(types.Defaulted(
        types.PrimitiveType(types.NumericType(types.Float)),
        "0.0",
      )),
      Ok(some_float),
    ),
    #(
      some_bool,
      types.ModifierType(types.Defaulted(
        types.PrimitiveType(types.Boolean),
        "False",
      )),
      Ok(some_bool),
    ),
    // Nested types
    #(
      dynamic.list([list_string, list_string]),
      types.CollectionType(
        types.List(
          types.CollectionType(types.List(types.PrimitiveType(types.String))),
        ),
      ),
      Ok(dynamic.list([list_string, list_string])),
    ),
    #(
      dynamic.properties([#(some_string, dict_string_int)]),
      types.CollectionType(types.Dict(
        types.PrimitiveType(types.String),
        types.CollectionType(types.Dict(
          types.PrimitiveType(types.String),
          types.PrimitiveType(types.NumericType(types.Integer)),
        )),
      )),
      Ok(dynamic.properties([#(some_string, dict_string_int)])),
    ),
    #(
      dynamic.list([dict_string_string]),
      types.CollectionType(
        types.List(
          types.CollectionType(types.Dict(
            types.PrimitiveType(types.String),
            types.PrimitiveType(types.String),
          )),
        ),
      ),
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
      types.PrimitiveType(types.Boolean),
      json_error(
        "expected (Bool) received (String) value (\"a\") for (some_key)",
      ),
    ),
    #(
      some_string,
      types.PrimitiveType(types.NumericType(types.Integer)),
      json_error(
        "expected (Int) received (String) value (\"a\") for (some_key)",
      ),
    ),
    #(
      some_string,
      types.PrimitiveType(types.NumericType(types.Float)),
      json_error(
        "expected (Float) received (String) value (\"a\") for (some_key)",
      ),
    ),
    #(
      some_bool,
      types.PrimitiveType(types.String),
      json_error(
        "expected (String) received (Bool) value (True) for (some_key)",
      ),
    ),
    // Dict types
    #(
      dynamic.properties([#(some_string, some_bool)]),
      types.CollectionType(types.Dict(
        types.PrimitiveType(types.String),
        types.PrimitiveType(types.String),
      )),
      json_error(
        "expected (String) received (Bool) value (Dict) for (some_key.a)",
      ),
    ),
    #(
      dynamic.properties([#(some_string, some_bool)]),
      types.CollectionType(types.Dict(
        types.PrimitiveType(types.String),
        types.PrimitiveType(types.NumericType(types.Integer)),
      )),
      json_error("expected (Int) received (Bool) value (Dict) for (some_key.a)"),
    ),
    #(
      dynamic.properties([#(some_string, some_bool)]),
      types.CollectionType(types.Dict(
        types.PrimitiveType(types.String),
        types.PrimitiveType(types.NumericType(types.Float)),
      )),
      json_error(
        "expected (Float) received (Bool) value (Dict) for (some_key.a)",
      ),
    ),
    #(
      dynamic.properties([#(some_string, some_string)]),
      types.CollectionType(types.Dict(
        types.PrimitiveType(types.String),
        types.PrimitiveType(types.Boolean),
      )),
      json_error(
        "expected (Bool) received (String) value (Dict) for (some_key.a)",
      ),
    ),
    // List types
    #(
      dynamic.list([some_string, some_bool]),
      types.CollectionType(types.List(types.PrimitiveType(types.String))),
      json_error(
        "expected (String) received (Bool) value (List) for (some_key.1)",
      ),
    ),
    #(
      dynamic.list([dynamic.int(1), some_bool]),
      types.CollectionType(
        types.List(types.PrimitiveType(types.NumericType(types.Integer))),
      ),
      json_error("expected (Int) received (Bool) value (List) for (some_key.1)"),
    ),
    #(
      dynamic.list([some_bool, some_string]),
      types.CollectionType(types.List(types.PrimitiveType(types.Boolean))),
      json_error(
        "expected (Bool) received (String) value (List) for (some_key.1)",
      ),
    ),
    #(
      dynamic.list([dynamic.float(1.1), some_bool]),
      types.CollectionType(
        types.List(types.PrimitiveType(types.NumericType(types.Float))),
      ),
      json_error(
        "expected (Float) received (Bool) value (List) for (some_key.1)",
      ),
    ),
    // Wrong structure types
    #(
      some_string,
      types.CollectionType(types.List(types.PrimitiveType(types.String))),
      json_error(
        "expected (List) received (String) value (\"a\") for (some_key)",
      ),
    ),
    #(
      some_string,
      types.CollectionType(types.Dict(
        types.PrimitiveType(types.String),
        types.PrimitiveType(types.String),
      )),
      json_error(
        "expected (Dict) received (String) value (\"a\") for (some_key)",
      ),
    ),
    // Multi-entry collection with one bad value
    #(
      dynamic.properties([
        #(some_string, other_string),
        #(dynamic.string("key2"), some_bool),
      ]),
      types.CollectionType(types.Dict(
        types.PrimitiveType(types.String),
        types.PrimitiveType(types.String),
      )),
      json_error(
        "expected (String) received (Bool) value (Dict) for (some_key.key2)",
      ),
    ),
    // List with first element wrong
    #(
      dynamic.list([some_bool, some_string]),
      types.CollectionType(types.List(types.PrimitiveType(types.String))),
      json_error(
        "expected (String) received (Bool) value (List) for (some_key.0)",
      ),
    ),
    // Optional types with wrong inner type
    #(
      some_bool,
      types.ModifierType(types.Optional(types.PrimitiveType(types.String))),
      json_error(
        "expected (String) received (Bool) value (True) for (some_key)",
      ),
    ),
    #(
      some_string,
      types.ModifierType(
        types.Optional(types.PrimitiveType(types.NumericType(types.Integer))),
      ),
      json_error(
        "expected (Int) received (String) value (\"a\") for (some_key)",
      ),
    ),
    // Optional List with wrong inner type
    #(
      dynamic.list([some_bool]),
      types.ModifierType(
        types.Optional(
          types.CollectionType(types.List(types.PrimitiveType(types.String))),
        ),
      ),
      json_error(
        "expected (String) received (Bool) value (List) for (some_key.0)",
      ),
    ),
    // Optional Dict with wrong value type
    #(
      dynamic.properties([#(some_string, some_bool)]),
      types.ModifierType(
        types.Optional(
          types.CollectionType(types.Dict(
            types.PrimitiveType(types.String),
            types.PrimitiveType(types.String),
          )),
        ),
      ),
      json_error(
        "expected (String) received (Bool) value (Dict) for (some_key.a)",
      ),
    ),
    // Defaulted types with wrong inner type
    #(
      some_bool,
      types.ModifierType(types.Defaulted(
        types.PrimitiveType(types.String),
        "default",
      )),
      json_error(
        "expected (String) received (Bool) value (True) for (some_key)",
      ),
    ),
    #(
      some_string,
      types.ModifierType(types.Defaulted(
        types.PrimitiveType(types.NumericType(types.Integer)),
        "0",
      )),
      json_error(
        "expected (Int) received (String) value (\"a\") for (some_key)",
      ),
    ),
    // Nested types with wrong inner type
    #(
      dynamic.list([dynamic.list([some_bool])]),
      types.CollectionType(
        types.List(
          types.CollectionType(types.List(types.PrimitiveType(types.String))),
        ),
      ),
      json_error(
        "expected (String) received (Bool) value (List) for (some_key.0.0)",
      ),
    ),
    #(
      dynamic.properties([
        #(some_string, dynamic.properties([#(some_string, some_bool)])),
      ]),
      types.CollectionType(types.Dict(
        types.PrimitiveType(types.String),
        types.CollectionType(types.Dict(
          types.PrimitiveType(types.String),
          types.PrimitiveType(types.String),
        )),
      )),
      json_error(
        "expected (String) received (Bool) value (Dict) for (some_key.a.a)",
      ),
    ),
    #(
      dynamic.list([dynamic.properties([#(some_string, some_bool)])]),
      types.CollectionType(
        types.List(
          types.CollectionType(types.Dict(
            types.PrimitiveType(types.String),
            types.PrimitiveType(types.String),
          )),
        ),
      ),
      json_error(
        "expected (String) received (Bool) value (List) for (some_key.0.a)",
      ),
    ),
  ]
  |> test_helpers.array_based_test_executor_2(fn(value, expected_type) {
    validations.validate_value_type(value, expected_type, "some_key")
  })
}

// ==== Inputs Validator ====
// missing_inputs_ok: False
// * ✅ happy path - no inputs
// * ✅ happy path - some inputs
// * ✅ happy path - optional param omitted
// * ✅ happy path - optional param provided
// * ✅ happy path - mix of required and optional, optional omitted
// * ✅ happy path - defaulted param omitted
// * ✅ happy path - defaulted param provided
// * ✅ happy path - mix of required and defaulted, defaulted omitted
// * ✅ happy path - refinement with defaulted inner omitted
// * ✅ missing inputs for params (single)
// * ✅ extra inputs
// * ✅ missing and extra inputs
// * ✅ type validation error - single
// * ✅ missing required when optional exists
// * ✅ missing required when defaulted exists
// missing_inputs_ok: True
// * ✅ happy path - no inputs when params exist (missing is OK)
// * ✅ happy path - partial inputs (some provided, some missing)
// * ✅ happy path - all inputs provided
// * ✅ extra inputs still rejected
// * ✅ type validation still enforced
pub fn inputs_validator_test() {
  [
    // ==== missing_inputs_ok: False ====
    // no inputs
    #(dict.new(), dict.new(), False, Ok(True)),
    // some inputs
    #(
      dict.from_list([
        #("name", types.PrimitiveType(types.String)),
        #("count", types.PrimitiveType(types.NumericType(types.Integer))),
      ]),
      dict.from_list([
        #("name", dynamic.string("foo")),
        #("count", dynamic.int(42)),
      ]),
      False,
      Ok(True),
    ),
    // optional param omitted - should pass
    #(
      dict.from_list([
        #(
          "maybe_name",
          types.ModifierType(types.Optional(types.PrimitiveType(types.String))),
        ),
      ]),
      dict.from_list([]),
      False,
      Ok(True),
    ),
    // optional param provided - should pass
    #(
      dict.from_list([
        #(
          "maybe_name",
          types.ModifierType(types.Optional(types.PrimitiveType(types.String))),
        ),
      ]),
      dict.from_list([#("maybe_name", dynamic.string("foo"))]),
      False,
      Ok(True),
    ),
    // mix of required and optional, optional omitted - should pass
    #(
      dict.from_list([
        #("name", types.PrimitiveType(types.String)),
        #(
          "maybe_count",
          types.ModifierType(
            types.Optional(
              types.PrimitiveType(types.NumericType(types.Integer)),
            ),
          ),
        ),
      ]),
      dict.from_list([#("name", dynamic.string("foo"))]),
      False,
      Ok(True),
    ),
    // defaulted param omitted - should pass
    #(
      dict.from_list([
        #(
          "count",
          types.ModifierType(types.Defaulted(
            types.PrimitiveType(types.NumericType(types.Integer)),
            "10",
          )),
        ),
      ]),
      dict.from_list([]),
      False,
      Ok(True),
    ),
    // defaulted param provided - should pass
    #(
      dict.from_list([
        #(
          "count",
          types.ModifierType(types.Defaulted(
            types.PrimitiveType(types.NumericType(types.Integer)),
            "10",
          )),
        ),
      ]),
      dict.from_list([#("count", dynamic.int(42))]),
      False,
      Ok(True),
    ),
    // mix of required and defaulted, defaulted omitted - should pass
    #(
      dict.from_list([
        #("name", types.PrimitiveType(types.String)),
        #(
          "count",
          types.ModifierType(types.Defaulted(
            types.PrimitiveType(types.NumericType(types.Integer)),
            "10",
          )),
        ),
      ]),
      dict.from_list([#("name", dynamic.string("foo"))]),
      False,
      Ok(True),
    ),
    // refinement with defaulted inner omitted - should pass (lcp_p75_latency style)
    #(
      dict.from_list([
        #("view_path", types.PrimitiveType(types.String)),
        #(
          "environment",
          types.RefinementType(types.OneOf(
            types.ModifierType(types.Defaulted(
              types.PrimitiveType(types.String),
              "production",
            )),
            set.from_list(["production"]),
          )),
        ),
      ]),
      dict.from_list([#("view_path", dynamic.string("/members/messages"))]),
      False,
      Ok(True),
    ),
    // missing inputs for params (single)
    #(
      dict.from_list([
        #("name", types.PrimitiveType(types.String)),
        #("count", types.PrimitiveType(types.NumericType(types.Integer))),
      ]),
      dict.from_list([#("name", dynamic.string("foo"))]),
      False,
      Error("Missing keys in input: count"),
    ),
    // extra inputs
    #(
      dict.from_list([
        #("name", types.PrimitiveType(types.String)),
      ]),
      dict.from_list([
        #("name", dynamic.string("foo")),
        #("extra", dynamic.int(42)),
      ]),
      False,
      Error("Extra keys in input: extra"),
    ),
    // missing and extra inputs
    #(
      dict.from_list([
        #("name", types.PrimitiveType(types.String)),
        #("required", types.PrimitiveType(types.Boolean)),
      ]),
      dict.from_list([
        #("name", dynamic.string("foo")),
        #("extra", dynamic.int(42)),
      ]),
      False,
      Error("Extra keys in input: extra and missing keys in input: required"),
    ),
    // type validation error - single
    #(
      dict.from_list([
        #("count", types.PrimitiveType(types.NumericType(types.Integer))),
      ]),
      dict.from_list([#("count", dynamic.string("not an int"))]),
      False,
      Error(
        "expected (Int) received (String) value (\"not an int\") for (count)",
      ),
    ),
    // missing required when optional param exists - should fail for required only
    #(
      dict.from_list([
        #("name", types.PrimitiveType(types.String)),
        #(
          "maybe_count",
          types.ModifierType(
            types.Optional(
              types.PrimitiveType(types.NumericType(types.Integer)),
            ),
          ),
        ),
      ]),
      dict.from_list([]),
      False,
      Error("Missing keys in input: name"),
    ),
    // missing required when defaulted param exists - should fail for required only
    #(
      dict.from_list([
        #("name", types.PrimitiveType(types.String)),
        #(
          "count",
          types.ModifierType(types.Defaulted(
            types.PrimitiveType(types.NumericType(types.Integer)),
            "10",
          )),
        ),
      ]),
      dict.from_list([]),
      False,
      Error("Missing keys in input: name"),
    ),
    // ==== missing_inputs_ok: True ====
    // no inputs when params exist - now OK
    #(
      dict.from_list([
        #("name", types.PrimitiveType(types.String)),
        #("count", types.PrimitiveType(types.NumericType(types.Integer))),
      ]),
      dict.from_list([]),
      True,
      Ok(True),
    ),
    // partial inputs - now OK
    #(
      dict.from_list([
        #("name", types.PrimitiveType(types.String)),
        #("count", types.PrimitiveType(types.NumericType(types.Integer))),
        #("flag", types.PrimitiveType(types.Boolean)),
      ]),
      dict.from_list([#("name", dynamic.string("foo"))]),
      True,
      Ok(True),
    ),
    // all inputs provided - still OK
    #(
      dict.from_list([
        #("name", types.PrimitiveType(types.String)),
        #("count", types.PrimitiveType(types.NumericType(types.Integer))),
      ]),
      dict.from_list([
        #("name", dynamic.string("foo")),
        #("count", dynamic.int(42)),
      ]),
      True,
      Ok(True),
    ),
    // extra inputs still rejected
    #(
      dict.from_list([
        #("name", types.PrimitiveType(types.String)),
      ]),
      dict.from_list([
        #("name", dynamic.string("foo")),
        #("extra", dynamic.int(42)),
      ]),
      True,
      Error("Extra keys in input: extra"),
    ),
    // type validation still enforced
    #(
      dict.from_list([
        #("count", types.PrimitiveType(types.NumericType(types.Integer))),
      ]),
      dict.from_list([#("count", dynamic.string("not an int"))]),
      True,
      Error(
        "expected (Int) received (String) value (\"not an int\") for (count)",
      ),
    ),
  ]
  |> list.each(fn(tuple) {
    let #(params, inputs, missing_inputs_ok, expected) = tuple
    validations.inputs_validator(params:, inputs:, missing_inputs_ok:)
    |> should.equal(expected)
  })

  // Tests where error order is not guaranteed (check contains)
  [
    // missing inputs for params (multiple) - missing_inputs_ok: False
    #(
      dict.from_list([
        #("name", types.PrimitiveType(types.String)),
        #("count", types.PrimitiveType(types.NumericType(types.Integer))),
        #("flag", types.PrimitiveType(types.Boolean)),
      ]),
      dict.from_list([#("name", dynamic.string("foo"))]),
      False,
      "Missing keys in input:",
    ),
    // type validation error - multiple - missing_inputs_ok: False
    #(
      dict.from_list([
        #("count", types.PrimitiveType(types.NumericType(types.Integer))),
        #("flag", types.PrimitiveType(types.Boolean)),
      ]),
      dict.from_list([
        #("count", dynamic.string("not an int")),
        #("flag", dynamic.string("not a bool")),
      ]),
      False,
      "expected (Int) received (String)",
    ),
  ]
  |> list.each(fn(tuple) {
    let #(params, inputs, missing_inputs_ok, expected_substring) = tuple
    let result =
      validations.inputs_validator(params:, inputs:, missing_inputs_ok:)
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
    validations.validate_relevant_uniqueness(
      things,
      by: fetch_name,
      label: "names",
    )
  })

  // sad paths - exact match
  [
    #(
      [#("alice", 1), #("alice", 2)],
      Error(errors.ParserDuplicateError("Duplicate names: alice")),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(things) {
    validations.validate_relevant_uniqueness(
      things,
      by: fetch_name,
      label: "names",
    )
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
      validations.validate_relevant_uniqueness(
        things,
        by: fetch_name,
        label: "names",
      )
    result |> should.be_error
    let assert Error(errors.ParserDuplicateError(msg)) = result
    string.contains(msg, expected_substring) |> should.be_true
  })
}

// ==== Validate Inputs For Collection Tests ====
// * ✅ happy path - empty collection
// * ✅ happy path - valid inputs (missing_inputs_ok: False)
// * ✅ happy path - partial inputs (missing_inputs_ok: True)
// * ✅ sad path - invalid inputs (missing_inputs_ok: False)
// * ✅ sad path - missing inputs rejected (missing_inputs_ok: False)
pub fn validate_inputs_for_collection_test() {
  // happy paths with missing_inputs_ok: False
  [
    [],
    [
      #(
        dict.from_list([#("name", dynamic.string("foo"))]),
        dict.from_list([
          #("name", types.PrimitiveType(types.String)),
        ]),
      ),
    ],
  ]
  |> list.each(fn(collection) {
    validations.validate_inputs_for_collection(
      input_param_collections: collection,
      get_inputs: fn(p) { p },
      get_params: fn(p) { p },
      with: fn(_) { "test" },
      missing_inputs_ok: False,
    )
    |> should.equal(Ok(True))
  })

  // happy path with missing_inputs_ok: True - partial inputs allowed
  let collection_partial = [
    #(
      dict.from_list([]),
      dict.from_list([
        #("name", types.PrimitiveType(types.String)),
        #("count", types.PrimitiveType(types.NumericType(types.Integer))),
      ]),
    ),
  ]
  validations.validate_inputs_for_collection(
    input_param_collections: collection_partial,
    get_inputs: fn(p) { p },
    get_params: fn(p) { p },
    with: fn(_) { "test" },
    missing_inputs_ok: True,
  )
  |> should.equal(Ok(True))

  // sad path - type error (both modes)
  let collection_type_error = [
    #(
      dict.from_list([#("count", dynamic.string("not an int"))]),
      dict.from_list([
        #("count", types.PrimitiveType(types.NumericType(types.Integer))),
      ]),
    ),
  ]
  validations.validate_inputs_for_collection(
    input_param_collections: collection_type_error,
    get_inputs: fn(p) { p },
    get_params: fn(p) { p },
    with: fn(_) { "test" },
    missing_inputs_ok: False,
  )
  |> should.be_error

  validations.validate_inputs_for_collection(
    input_param_collections: collection_type_error,
    get_inputs: fn(p) { p },
    get_params: fn(p) { p },
    with: fn(_) { "test" },
    missing_inputs_ok: True,
  )
  |> should.be_error

  // sad path - missing inputs rejected when missing_inputs_ok: False
  validations.validate_inputs_for_collection(
    input_param_collections: collection_partial,
    get_inputs: fn(p) { p },
    get_params: fn(p) { p },
    with: fn(_) { "test" },
    missing_inputs_ok: False,
  )
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
      in: reference,
      against: referrer,
      with: error_prefix,
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
