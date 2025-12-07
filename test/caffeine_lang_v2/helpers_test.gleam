import caffeine_lang_v2/common/helpers
import gleam/dynamic
import gleam/list
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
    helpers.validate_value_type(value, expected_type)
    |> should.be_ok
  })

  // sad paths
  [
    // Basic types
    #(some_string, helpers.Boolean, "expected (Bool) received (String) for ()"),
    #(some_string, helpers.Integer, "expected (Int) received (String) for ()"),
    #(some_string, helpers.Float, "expected (Float) received (String) for ()"),
    #(some_bool, helpers.String, "expected (String) received (Bool) for ()"),
    // Dict types
    #(
      dynamic.properties([#(some_string, some_bool)]),
      helpers.Dict(helpers.String, helpers.String),
      "expected (String) received (Bool) for ()",
    ),
    #(
      dynamic.properties([#(some_string, some_bool)]),
      helpers.Dict(helpers.String, helpers.Integer),
      "expected (Int) received (Bool) for ()",
    ),
    #(
      dynamic.properties([#(some_string, some_bool)]),
      helpers.Dict(helpers.String, helpers.Float),
      "expected (Float) received (Bool) for ()",
    ),
    #(
      dynamic.properties([#(some_string, some_string)]),
      helpers.Dict(helpers.String, helpers.Boolean),
      "expected (Bool) received (String) for ()",
    ),
    // List types
    #(
      dynamic.list([some_string, some_bool]),
      helpers.List(helpers.String),
      "expected (String) received (Bool) for ()",
    ),
    #(
      dynamic.list([dynamic.int(1), some_bool]),
      helpers.List(helpers.Integer),
      "expected (Int) received (Bool) for ()",
    ),
    #(
      dynamic.list([some_bool, some_string]),
      helpers.List(helpers.Boolean),
      "expected (Bool) received (String) for ()",
    ),
    #(
      dynamic.list([dynamic.float(1.1), some_bool]),
      helpers.List(helpers.Float),
      "expected (Float) received (Bool) for ()",
    ),
    // Wrong structure types
    #(
      some_string,
      helpers.List(helpers.String),
      "expected (List) received (String) for ()",
    ),
    #(
      some_string,
      helpers.Dict(helpers.String, helpers.String),
      "expected (Dict) received (String) for ()",
    ),
  ]
  |> list.each(fn(tuple) {
    let #(value, expected_type, msg) = tuple
    helpers.validate_value_type(value, expected_type)
    |> should.equal(Error(helpers.JsonParserError(msg)))
  })
}
