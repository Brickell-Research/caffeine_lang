import caffeine_lang/common/accepted_types.{type AcceptedTypes}
import caffeine_lang/common/modifier_types
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/common/refinement_types
import gleam/dynamic
import gleam/result
import gleam/set
import test_helpers

// ==== parse_refinement_type ====
// ==== Happy Path ====
// * ✅ Refinement(Integer)
// * ✅ Refinement(Float)
// * ✅ Refinement(String)
// * ✅ Refinement(Defaulted(String, default))
// * ✅ Refinement(Defaulted(Integer, 10))
// * ✅ Refinement(Defaulted(Float, 1.5))
// ==== Sad Path ====
// * ✅ Refinement(Integer) - with empty set
// * ✅ Refinement(Float) - with empty set
// * ✅ Refinement(String) - with empty set
// * ✅ Refinement(Integer) - with invalid types in set
// * ✅ Refinement(Float) - with invalid types in set
// * ✅ Refinement(String) - with invalid types in set
// * ✅ Refinement(Unknown) - invalid inner type
// * ✅ Refinement(Boolean)
// * ✅ Refinement(List(String))
// * ✅ Refinement(Dict(String, String))
// * ✅ Refinement(Optional(String))
// * ✅ Refinement(Defaulted(Boolean, True)) - Boolean not supported
// * ✅ Refinement(Defaulted(List(String), a)) - List not supported
// * ✅ Refinement(Defaulted(Dict(String, String), a)) - Dict not supported
// * ✅ Refinement(Defaulted(Optional(String), a)) - Optional not supported
// * ✅ Malformed syntax - missing outer closing bracket
// * ✅ Malformed syntax - missing inner opening bracket
// * ✅ Malformed syntax - missing outer opening bracket
// * ✅ Malformed syntax - wrong variable name (y instead of x)
// * ✅ Malformed syntax - wrong case (IN instead of in)
// * ✅ Malformed syntax - missing space after opening bracket
// * ✅ Malformed syntax - missing space before pipe
// * ✅ Malformed syntax - missing space after pipe
// * ✅ Malformed syntax - missing space after "x"
// * ✅ Malformed syntax - missing space before inner opening bracket
// * ✅ Malformed syntax - missing space after inner opening bracket
pub fn parse_refinement_type_test() {
  [
    #(
      "Integer { x | x in { 10, 20, 30 } }",
      Ok(refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    #(
      "Float { x | x in { 10.0, 20.0, 30.0 } }",
      Ok(refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Float,
        )),
        set.from_list(["10.0", "20.0", "30.0"]),
      )),
    ),
    #(
      "String { x | x in { pizza, pasta, salad, tasty-food } }",
      Ok(refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.String),
        set.from_list(["pizza", "pasta", "salad", "tasty-food"]),
      )),
    ),
    #("Boolean { x | x in { True, False } }", Error(Nil)),
    // Sad path - empty set
    #("Integer { x | x in {  } }", Error(Nil)),
    #("Float { x | x in {  } }", Error(Nil)),
    #("String { x | x in {  } }", Error(Nil)),
    // Sad path - invalid types in set
    #("Integer { x | x in { 10.0 } }", Error(Nil)),
    #("Float { x | x in { pizza } }", Error(Nil)),
    #(
      "String { x | x in { 10 } }",
      Ok(refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.String),
        set.from_list(["10"]),
      )),
    ),
    // Sad path - invalid inner type (parse_inner returns Error)
    #("Unknown { x | x in { 1, 2, 3 } }", Error(Nil)),
    // Sad path - List/Dict/Optional not supported
    #("List(String) { x | x in { a, b, c } }", Error(Nil)),
    #("Dict(String, String) { x | x in { a, b, c } }", Error(Nil)),
    #("Optional(String) { x | x in { a, b, c } }", Error(Nil)),
    // Happy path - Defaulted is supported
    #(
      "Defaulted(String, default) { x | x in { a, b, c } }",
      Ok(refinement_types.OneOf(
        accepted_types.ModifierType(modifier_types.Defaulted(
          accepted_types.PrimitiveType(primitive_types.String),
          "default",
        )),
        set.from_list(["a", "b", "c"]),
      )),
    ),
    #(
      "Defaulted(Integer, 10) { x | x in { 10, 20, 30 } }",
      Ok(refinement_types.OneOf(
        accepted_types.ModifierType(modifier_types.Defaulted(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          "10",
        )),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    #(
      "Defaulted(Float, 1.5) { x | x in { 1.5, 2.5, 3.5 } }",
      Ok(refinement_types.OneOf(
        accepted_types.ModifierType(modifier_types.Defaulted(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Float,
          )),
          "1.5",
        )),
        set.from_list(["1.5", "2.5", "3.5"]),
      )),
    ),
    // Sad path - Defaulted with unsupported inner types
    #("Defaulted(Boolean, True) { x | x in { True, False } }", Error(Nil)),
    #("Defaulted(List(String), a) { x | x in { a, b, c } }", Error(Nil)),
    #("Defaulted(Dict(String, String), a) { x | x in { a, b } }", Error(Nil)),
    #("Defaulted(Optional(String), a) { x | x in { a, b, c } }", Error(Nil)),
    // Sad path - malformed syntax / missing brackets
    #("Integer { x | x in { 10, 20, 30 }", Error(Nil)),
    #("Integer { x | x in 10, 20, 30 } }", Error(Nil)),
    #("Integer x | x in { 10, 20, 30 } }", Error(Nil)),
    #("Integer { y | y in { 10, 20, 30 } }", Error(Nil)),
    #("Integer { x | x IN { 10, 20, 30 } }", Error(Nil)),
    #("Integer {x | x in { 10, 20, 30 } }", Error(Nil)),
    #("Integer { x| x in { 10, 20, 30 } }", Error(Nil)),
    #("Integer { x |x in { 10, 20, 30 } }", Error(Nil)),
    #("Integer { x | xin { 10, 20, 30 } }", Error(Nil)),
    #("Integer { x | x in{ 10, 20, 30 } }", Error(Nil)),
    #("Integer { x | x in {10, 20, 30 } }", Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    refinement_types.parse_refinement_type(
      input,
      parse_primitive_or_defaulted,
      validate_string_literal,
    )
  })
}

// ==== refinement_type_to_string ====
// * ✅ OneOf(T, {}) -> "T {x | x in {...} }"
//   * ✅ Integer
//   * ✅ Float
//   * ✅ String
//   * ✅ Defaulted(String, default)
//   * ✅ Defaulted(Integer, 10)
pub fn refinement_type_to_string_test() {
  [
    #(
      refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        set.from_list(["10", "20", "30"]),
      ),
      "Integer { x | x in { 10, 20, 30 } }",
    ),
    #(
      refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Float,
        )),
        set.from_list(["10.0", "20.0", "30.0"]),
      ),
      "Float { x | x in { 10.0, 20.0, 30.0 } }",
    ),
    #(
      refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.String),
        set.from_list(["pasta", "pizza", "salad"]),
      ),
      "String { x | x in { pasta, pizza, salad } }",
    ),
    #(
      refinement_types.OneOf(
        accepted_types.ModifierType(modifier_types.Defaulted(
          accepted_types.PrimitiveType(primitive_types.String),
          "default",
        )),
        set.from_list(["a", "b", "c"]),
      ),
      "Defaulted(String, default) { x | x in { a, b, c } }",
    ),
    #(
      refinement_types.OneOf(
        accepted_types.ModifierType(modifier_types.Defaulted(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          "10",
        )),
        set.from_list(["10", "20", "30"]),
      ),
      "Defaulted(Integer, 10) { x | x in { 10, 20, 30 } }",
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    refinement_types.refinement_type_to_string(
      input,
      accepted_types.accepted_type_to_string,
    )
  })
}

// ==== validate_value ====
// * ✅ OneOf(Integer) - happy + sad
// * ✅ OneOf(Float) - happy + sad
// * ✅ OneOf(String) - happy + sad
// * ✅ OneOf(Defaulted(String, default)) - happy + sad
// * ✅ OneOf - wrong type entirely -> Error
pub fn validate_value_test() {
  [
    // Integer happy path - value in set
    #(
      #(
        refinement_types.OneOf(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          set.from_list(["10", "20", "30"]),
        ),
        dynamic.int(10),
      ),
      True,
    ),
    // Integer sad path - value not in set
    #(
      #(
        refinement_types.OneOf(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          set.from_list(["10", "20", "30"]),
        ),
        dynamic.int(99),
      ),
      False,
    ),
    // Float happy path - value in set
    #(
      #(
        refinement_types.OneOf(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Float,
          )),
          set.from_list(["1.5", "2.5", "3.5"]),
        ),
        dynamic.float(1.5),
      ),
      True,
    ),
    // Float sad path - value not in set
    #(
      #(
        refinement_types.OneOf(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Float,
          )),
          set.from_list(["1.5", "2.5", "3.5"]),
        ),
        dynamic.float(9.9),
      ),
      False,
    ),
    // String happy path - value in set
    #(
      #(
        refinement_types.OneOf(
          accepted_types.PrimitiveType(primitive_types.String),
          set.from_list(["pizza", "pasta", "salad"]),
        ),
        dynamic.string("pizza"),
      ),
      True,
    ),
    // String sad path - value not in set
    #(
      #(
        refinement_types.OneOf(
          accepted_types.PrimitiveType(primitive_types.String),
          set.from_list(["pizza", "pasta", "salad"]),
        ),
        dynamic.string("burger"),
      ),
      False,
    ),
    // Defaulted(String, default) happy path - value in set
    #(
      #(
        refinement_types.OneOf(
          accepted_types.ModifierType(modifier_types.Defaulted(
            accepted_types.PrimitiveType(primitive_types.String),
            "default",
          )),
          set.from_list(["a", "b", "c", "default"]),
        ),
        dynamic.string("a"),
      ),
      True,
    ),
    // Defaulted(String, default) sad path - value not in set
    #(
      #(
        refinement_types.OneOf(
          accepted_types.ModifierType(modifier_types.Defaulted(
            accepted_types.PrimitiveType(primitive_types.String),
            "default",
          )),
          set.from_list(["a", "b", "c"]),
        ),
        dynamic.string("z"),
      ),
      False,
    ),
    // Wrong type entirely - string when expecting integer
    #(
      #(
        refinement_types.OneOf(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          set.from_list(["10", "20", "30"]),
        ),
        dynamic.string("not an integer"),
      ),
      False,
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    case
      refinement_types.validate_value(
        typ,
        value,
        accepted_types.decode_value_to_string,
      )
    {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

// ==== resolve_to_string ====
// * ✅ OneOf(Integer) - resolves value to string
// * ✅ OneOf(Float) - resolves value to string
// * ✅ OneOf(String) - resolves value to string
// * ✅ OneOf(Defaulted(String, default)) - resolves value to string
// * ✅ OneOf - decode error returns Error
pub fn resolve_to_string_test() {
  let resolve_string = fn(x: String) { x }

  [
    // Integer happy path
    #(
      #(
        refinement_types.OneOf(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          set.from_list(["10", "20", "30"]),
        ),
        dynamic.int(10),
      ),
      Ok("10"),
    ),
    // Float happy path
    #(
      #(
        refinement_types.OneOf(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Float,
          )),
          set.from_list(["1.5", "2.5", "3.5"]),
        ),
        dynamic.float(1.5),
      ),
      Ok("1.5"),
    ),
    // String happy path
    #(
      #(
        refinement_types.OneOf(
          accepted_types.PrimitiveType(primitive_types.String),
          set.from_list(["pasta", "pizza", "salad"]),
        ),
        dynamic.string("pizza"),
      ),
      Ok("pizza"),
    ),
    // Defaulted(String, default) happy path
    #(
      #(
        refinement_types.OneOf(
          accepted_types.ModifierType(modifier_types.Defaulted(
            accepted_types.PrimitiveType(primitive_types.String),
            "default",
          )),
          set.from_list(["a", "b", "c"]),
        ),
        dynamic.string("a"),
      ),
      Ok("a"),
    ),
    // Decode error - wrong type
    #(
      #(
        refinement_types.OneOf(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          set.from_list(["10", "20", "30"]),
        ),
        dynamic.string("not an integer"),
      ),
      Error("Unable to decode refinement type value."),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    refinement_types.resolve_to_string(
      typ,
      value,
      accepted_types.decode_value_to_string,
      resolve_string,
    )
  })
}

/// Parser for refinement-compatible types (Integer, Float, String, or Defaulted with those).
fn parse_primitive_or_defaulted(raw: String) -> Result(AcceptedTypes, Nil) {
  case parse_refinement_compatible_primitive(raw) {
    Ok(prim) -> Ok(accepted_types.PrimitiveType(prim))
    Error(_) ->
      case
        modifier_types.parse_modifier_type(
          raw,
          parse_refinement_compatible,
          validate_refinement_compatible_default,
        )
      {
        Ok(modifier) -> Ok(accepted_types.ModifierType(modifier))
        Error(_) -> Error(Nil)
      }
  }
}

/// Parser for refinement-compatible primitives only (Integer, Float, String - not Boolean).
fn parse_refinement_compatible(raw: String) -> Result(AcceptedTypes, Nil) {
  parse_refinement_compatible_primitive(raw)
  |> result.map(accepted_types.PrimitiveType)
}

/// Parses only Integer, Float, or String primitives (excludes Boolean).
fn parse_refinement_compatible_primitive(
  raw: String,
) -> Result(primitive_types.PrimitiveTypes, Nil) {
  case raw {
    "String" -> Ok(primitive_types.String)
    "Integer" -> Ok(primitive_types.NumericType(numeric_types.Integer))
    "Float" -> Ok(primitive_types.NumericType(numeric_types.Float))
    _ -> Error(Nil)
  }
}

/// Validates a string literal value is valid for an AcceptedTypes.
fn validate_string_literal(
  typ: AcceptedTypes,
  value: String,
) -> Result(Nil, Nil) {
  case typ {
    accepted_types.PrimitiveType(primitive) ->
      primitive_types.validate_default_value(primitive, value)
    accepted_types.ModifierType(modifier_types.Defaulted(inner, _)) ->
      validate_string_literal(inner, value)
    _ -> Error(Nil)
  }
}

/// Validates a default value for refinement-compatible primitives only.
fn validate_refinement_compatible_default(
  typ: AcceptedTypes,
  value: String,
) -> Result(Nil, Nil) {
  case typ {
    accepted_types.PrimitiveType(primitive_types.String) -> Ok(Nil)
    accepted_types.PrimitiveType(primitive_types.NumericType(numeric)) ->
      numeric_types.validate_default_value(numeric, value)
    _ -> Error(Nil)
  }
}
