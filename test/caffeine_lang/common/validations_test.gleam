import caffeine_lang/common/accepted_types.{
  Boolean, CollectionType, Defaulted, Dict, Float, Integer, List, ModifierType,
  Optional, PrimitiveType, String,
}
import caffeine_lang/common/errors
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
    #(some_bool, PrimitiveType(Boolean), Ok(some_bool)),
    #(some_int, PrimitiveType(Integer), Ok(some_int)),
    #(some_float, PrimitiveType(Float), Ok(some_float)),
    #(some_string, PrimitiveType(String), Ok(some_string)),
    // Dict types
    #(
      dict_string_string,
      CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
      Ok(dict_string_string),
    ),
    #(
      dict_string_int,
      CollectionType(Dict(PrimitiveType(String), PrimitiveType(Integer))),
      Ok(dict_string_int),
    ),
    #(
      dict_string_float,
      CollectionType(Dict(PrimitiveType(String), PrimitiveType(Float))),
      Ok(dict_string_float),
    ),
    #(
      dict_string_bool,
      CollectionType(Dict(PrimitiveType(String), PrimitiveType(Boolean))),
      Ok(dict_string_bool),
    ),
    // List types
    #(list_string, CollectionType(List(PrimitiveType(String))), Ok(list_string)),
    #(list_int, CollectionType(List(PrimitiveType(Integer))), Ok(list_int)),
    #(list_bool, CollectionType(List(PrimitiveType(Boolean))), Ok(list_bool)),
    #(list_float, CollectionType(List(PrimitiveType(Float))), Ok(list_float)),
    // Empty collections
    #(empty_list, CollectionType(List(PrimitiveType(String))), Ok(empty_list)),
    #(
      empty_dict,
      CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
      Ok(empty_dict),
    ),
    // Optional types with values
    #(
      some_string,
      ModifierType(Optional(PrimitiveType(String))),
      Ok(some_string),
    ),
    #(some_int, ModifierType(Optional(PrimitiveType(Integer))), Ok(some_int)),
    #(some_float, ModifierType(Optional(PrimitiveType(Float))), Ok(some_float)),
    #(some_bool, ModifierType(Optional(PrimitiveType(Boolean))), Ok(some_bool)),
    // Optional List types
    #(
      list_string,
      ModifierType(Optional(CollectionType(List(PrimitiveType(String))))),
      Ok(list_string),
    ),
    // Optional Dict types
    #(
      dict_string_string,
      ModifierType(
        Optional(
          CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
        ),
      ),
      Ok(dict_string_string),
    ),
    // Defaulted types with values
    #(
      some_string,
      ModifierType(Defaulted(PrimitiveType(String), "default")),
      Ok(some_string),
    ),
    #(
      some_int,
      ModifierType(Defaulted(PrimitiveType(Integer), "0")),
      Ok(some_int),
    ),
    #(
      some_float,
      ModifierType(Defaulted(PrimitiveType(Float), "0.0")),
      Ok(some_float),
    ),
    #(
      some_bool,
      ModifierType(Defaulted(PrimitiveType(Boolean), "False")),
      Ok(some_bool),
    ),
    // Nested types
    #(
      dynamic.list([list_string, list_string]),
      CollectionType(List(CollectionType(List(PrimitiveType(String))))),
      Ok(dynamic.list([list_string, list_string])),
    ),
    #(
      dynamic.properties([#(some_string, dict_string_int)]),
      CollectionType(
        Dict(
          PrimitiveType(String),
          CollectionType(Dict(PrimitiveType(String), PrimitiveType(Integer))),
        ),
      ),
      Ok(dynamic.properties([#(some_string, dict_string_int)])),
    ),
    #(
      dynamic.list([dict_string_string]),
      CollectionType(
        List(CollectionType(Dict(PrimitiveType(String), PrimitiveType(String)))),
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
      PrimitiveType(Boolean),
      json_error("expected (Bool) received (String) for (some_key)"),
    ),
    #(
      some_string,
      PrimitiveType(Integer),
      json_error("expected (Int) received (String) for (some_key)"),
    ),
    #(
      some_string,
      PrimitiveType(Float),
      json_error("expected (Float) received (String) for (some_key)"),
    ),
    #(
      some_bool,
      PrimitiveType(String),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    // Dict types
    #(
      dynamic.properties([#(some_string, some_bool)]),
      CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    #(
      dynamic.properties([#(some_string, some_bool)]),
      CollectionType(Dict(PrimitiveType(String), PrimitiveType(Integer))),
      json_error("expected (Int) received (Bool) for (some_key)"),
    ),
    #(
      dynamic.properties([#(some_string, some_bool)]),
      CollectionType(Dict(PrimitiveType(String), PrimitiveType(Float))),
      json_error("expected (Float) received (Bool) for (some_key)"),
    ),
    #(
      dynamic.properties([#(some_string, some_string)]),
      CollectionType(Dict(PrimitiveType(String), PrimitiveType(Boolean))),
      json_error("expected (Bool) received (String) for (some_key)"),
    ),
    // List types
    #(
      dynamic.list([some_string, some_bool]),
      CollectionType(List(PrimitiveType(String))),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    #(
      dynamic.list([dynamic.int(1), some_bool]),
      CollectionType(List(PrimitiveType(Integer))),
      json_error("expected (Int) received (Bool) for (some_key)"),
    ),
    #(
      dynamic.list([some_bool, some_string]),
      CollectionType(List(PrimitiveType(Boolean))),
      json_error("expected (Bool) received (String) for (some_key)"),
    ),
    #(
      dynamic.list([dynamic.float(1.1), some_bool]),
      CollectionType(List(PrimitiveType(Float))),
      json_error("expected (Float) received (Bool) for (some_key)"),
    ),
    // Wrong structure types
    #(
      some_string,
      CollectionType(List(PrimitiveType(String))),
      json_error("expected (List) received (String) for (some_key)"),
    ),
    #(
      some_string,
      CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
      json_error("expected (Dict) received (String) for (some_key)"),
    ),
    // Multi-entry collection with one bad value
    #(
      dynamic.properties([
        #(some_string, other_string),
        #(dynamic.string("key2"), some_bool),
      ]),
      CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    // List with first element wrong
    #(
      dynamic.list([some_bool, some_string]),
      CollectionType(List(PrimitiveType(String))),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    // Optional types with wrong inner type
    #(
      some_bool,
      ModifierType(Optional(PrimitiveType(String))),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    #(
      some_string,
      ModifierType(Optional(PrimitiveType(Integer))),
      json_error("expected (Int) received (String) for (some_key)"),
    ),
    // Optional List with wrong inner type
    #(
      dynamic.list([some_bool]),
      ModifierType(Optional(CollectionType(List(PrimitiveType(String))))),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    // Optional Dict with wrong value type
    #(
      dynamic.properties([#(some_string, some_bool)]),
      ModifierType(
        Optional(
          CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
        ),
      ),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    // Defaulted types with wrong inner type
    #(
      some_bool,
      ModifierType(Defaulted(PrimitiveType(String), "default")),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    #(
      some_string,
      ModifierType(Defaulted(PrimitiveType(Integer), "0")),
      json_error("expected (Int) received (String) for (some_key)"),
    ),
    // Nested types with wrong inner type
    #(
      dynamic.list([dynamic.list([some_bool])]),
      CollectionType(List(CollectionType(List(PrimitiveType(String))))),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    #(
      dynamic.properties([
        #(some_string, dynamic.properties([#(some_string, some_bool)])),
      ]),
      CollectionType(
        Dict(
          PrimitiveType(String),
          CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
        ),
      ),
      json_error("expected (String) received (Bool) for (some_key)"),
    ),
    #(
      dynamic.list([dynamic.properties([#(some_string, some_bool)])]),
      CollectionType(
        List(CollectionType(Dict(PrimitiveType(String), PrimitiveType(String)))),
      ),
      json_error("expected (String) received (Bool) for (some_key)"),
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
        #("name", PrimitiveType(String)),
        #("count", PrimitiveType(Integer)),
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
        #("maybe_name", ModifierType(Optional(PrimitiveType(String)))),
      ]),
      dict.from_list([]),
      False,
      Ok(True),
    ),
    // optional param provided - should pass
    #(
      dict.from_list([
        #("maybe_name", ModifierType(Optional(PrimitiveType(String)))),
      ]),
      dict.from_list([#("maybe_name", dynamic.string("foo"))]),
      False,
      Ok(True),
    ),
    // mix of required and optional, optional omitted - should pass
    #(
      dict.from_list([
        #("name", PrimitiveType(String)),
        #("maybe_count", ModifierType(Optional(PrimitiveType(Integer)))),
      ]),
      dict.from_list([#("name", dynamic.string("foo"))]),
      False,
      Ok(True),
    ),
    // defaulted param omitted - should pass
    #(
      dict.from_list([
        #("count", ModifierType(Defaulted(PrimitiveType(Integer), "10"))),
      ]),
      dict.from_list([]),
      False,
      Ok(True),
    ),
    // defaulted param provided - should pass
    #(
      dict.from_list([
        #("count", ModifierType(Defaulted(PrimitiveType(Integer), "10"))),
      ]),
      dict.from_list([#("count", dynamic.int(42))]),
      False,
      Ok(True),
    ),
    // mix of required and defaulted, defaulted omitted - should pass
    #(
      dict.from_list([
        #("name", PrimitiveType(String)),
        #("count", ModifierType(Defaulted(PrimitiveType(Integer), "10"))),
      ]),
      dict.from_list([#("name", dynamic.string("foo"))]),
      False,
      Ok(True),
    ),
    // missing inputs for params (single)
    #(
      dict.from_list([
        #("name", PrimitiveType(String)),
        #("count", PrimitiveType(Integer)),
      ]),
      dict.from_list([#("name", dynamic.string("foo"))]),
      False,
      Error("Missing keys in input: count"),
    ),
    // extra inputs
    #(
      dict.from_list([#("name", PrimitiveType(String))]),
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
        #("name", PrimitiveType(String)),
        #("required", PrimitiveType(Boolean)),
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
      dict.from_list([#("count", PrimitiveType(Integer))]),
      dict.from_list([#("count", dynamic.string("not an int"))]),
      False,
      Error("expected (Int) received (String) for (count)"),
    ),
    // missing required when optional param exists - should fail for required only
    #(
      dict.from_list([
        #("name", PrimitiveType(String)),
        #("maybe_count", ModifierType(Optional(PrimitiveType(Integer)))),
      ]),
      dict.from_list([]),
      False,
      Error("Missing keys in input: name"),
    ),
    // missing required when defaulted param exists - should fail for required only
    #(
      dict.from_list([
        #("name", PrimitiveType(String)),
        #("count", ModifierType(Defaulted(PrimitiveType(Integer), "10"))),
      ]),
      dict.from_list([]),
      False,
      Error("Missing keys in input: name"),
    ),
    // ==== missing_inputs_ok: True ====
    // no inputs when params exist - now OK
    #(
      dict.from_list([
        #("name", PrimitiveType(String)),
        #("count", PrimitiveType(Integer)),
      ]),
      dict.from_list([]),
      True,
      Ok(True),
    ),
    // partial inputs - now OK
    #(
      dict.from_list([
        #("name", PrimitiveType(String)),
        #("count", PrimitiveType(Integer)),
        #("flag", PrimitiveType(Boolean)),
      ]),
      dict.from_list([#("name", dynamic.string("foo"))]),
      True,
      Ok(True),
    ),
    // all inputs provided - still OK
    #(
      dict.from_list([
        #("name", PrimitiveType(String)),
        #("count", PrimitiveType(Integer)),
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
      dict.from_list([#("name", PrimitiveType(String))]),
      dict.from_list([
        #("name", dynamic.string("foo")),
        #("extra", dynamic.int(42)),
      ]),
      True,
      Error("Extra keys in input: extra"),
    ),
    // type validation still enforced
    #(
      dict.from_list([#("count", PrimitiveType(Integer))]),
      dict.from_list([#("count", dynamic.string("not an int"))]),
      True,
      Error("expected (Int) received (String) for (count)"),
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
        #("name", PrimitiveType(String)),
        #("count", PrimitiveType(Integer)),
        #("flag", PrimitiveType(Boolean)),
      ]),
      dict.from_list([#("name", dynamic.string("foo"))]),
      False,
      "Missing keys in input:",
    ),
    // type validation error - multiple - missing_inputs_ok: False
    #(
      dict.from_list([
        #("count", PrimitiveType(Integer)),
        #("flag", PrimitiveType(Boolean)),
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
        dict.from_list([#("name", PrimitiveType(String))]),
      ),
    ],
  ]
  |> list.each(fn(collection) {
    validations.validate_inputs_for_collection(
      input_param_collections: collection,
      get_inputs: fn(p) { p },
      get_params: fn(p) { p },
      missing_inputs_ok: False,
    )
    |> should.equal(Ok(True))
  })

  // happy path with missing_inputs_ok: True - partial inputs allowed
  let collection_partial = [
    #(
      dict.from_list([]),
      dict.from_list([
        #("name", PrimitiveType(String)),
        #("count", PrimitiveType(Integer)),
      ]),
    ),
  ]
  validations.validate_inputs_for_collection(
    input_param_collections: collection_partial,
    get_inputs: fn(p) { p },
    get_params: fn(p) { p },
    missing_inputs_ok: True,
  )
  |> should.equal(Ok(True))

  // sad path - type error (both modes)
  let collection_type_error = [
    #(
      dict.from_list([#("count", dynamic.string("not an int"))]),
      dict.from_list([#("count", PrimitiveType(Integer))]),
    ),
  ]
  validations.validate_inputs_for_collection(
    input_param_collections: collection_type_error,
    get_inputs: fn(p) { p },
    get_params: fn(p) { p },
    missing_inputs_ok: False,
  )
  |> should.be_error

  validations.validate_inputs_for_collection(
    input_param_collections: collection_type_error,
    get_inputs: fn(p) { p },
    get_params: fn(p) { p },
    missing_inputs_ok: True,
  )
  |> should.be_error

  // sad path - missing inputs rejected when missing_inputs_ok: False
  validations.validate_inputs_for_collection(
    input_param_collections: collection_partial,
    get_inputs: fn(p) { p },
    get_params: fn(p) { p },
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
