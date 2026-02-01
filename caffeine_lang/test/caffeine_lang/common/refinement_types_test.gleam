import caffeine_lang/common/accepted_types.{type AcceptedTypes}
import caffeine_lang/common/modifier_types
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/common/refinement_types
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleam/set
import gleeunit/should
import test_helpers

// ==== parse_refinement_type ====
// ==== Happy Path (OneOf) ====
// * ✅ Refinement(Integer)
// * ✅ Refinement(Float)
// * ✅ Refinement(String)
// * ✅ Refinement(Defaulted(String, default))
// * ✅ Refinement(Defaulted(Integer, 10))
// * ✅ Refinement(Defaulted(Float, 1.5))
// * ✅ OneOf - flexible spacing (no spaces around inner braces)
// * ✅ OneOf - flexible spacing (no space after opening inner brace)
// * ✅ OneOf - flexible spacing (no space before closing inner brace)
// * ✅ OneOf - flexible spacing (no space after outer opening brace)
// * ✅ OneOf - flexible spacing (no space before pipe)
// * ✅ OneOf - flexible spacing (no space after pipe)
// * ✅ OneOf - flexible spacing (no space before inner opening brace)
// ==== Happy Path (InclusiveRange) ====
// * ✅ InclusiveRange(Integer) - basic range
// * ✅ InclusiveRange(Integer) - negative range
// * ✅ InclusiveRange(Integer) - zero crossing range
// * ✅ InclusiveRange(Float) - basic range
// * ✅ InclusiveRange(Float) - negative range
// * ✅ InclusiveRange(Float) - zero crossing range
// * ✅ InclusiveRange - flexible spacing (no spaces around parens)
// * ✅ InclusiveRange - flexible spacing (no space after opening paren)
// * ✅ InclusiveRange - flexible spacing (no space before closing paren)
// * ✅ InclusiveRange - flexible spacing (no space after outer opening brace)
// * ✅ InclusiveRange - flexible spacing (no space before pipe)
// * ✅ InclusiveRange - flexible spacing (no space after pipe)
// * ✅ InclusiveRange - flexible spacing (no space before opening paren)
// ==== Sad Path (OneOf) ====
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
// * ✅ Malformed syntax - missing space between x and in (xin)
// * ✅ OneOf - duplicate values in set (invalid)
// ==== Sad Path (InclusiveRange) ====
// * ✅ InclusiveRange(String) - not supported (only Integer/Float)
// * ✅ InclusiveRange(Integer) - non-integer bounds
// * ✅ InclusiveRange(Float) - non-float bounds
// * ✅ InclusiveRange - missing bounds
// * ✅ InclusiveRange - too many bounds
// * ✅ InclusiveRange - malformed syntax (wrong parens)
// * ✅ InclusiveRange(Integer) - low > high (invalid range)
// * ✅ InclusiveRange(Float) - low > high (invalid range)
// * ✅ InclusiveRange(Defaulted(Integer, 50)) - Defaulted not supported
// * ✅ InclusiveRange(Defaulted(Float, 1.5)) - Defaulted not supported
pub fn parse_refinement_type_test() {
  [
    // ==== Happy Path (OneOf) ====
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
    #(
      "String { x | x in { 10 } }",
      Ok(refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.String),
        set.from_list(["10"]),
      )),
    ),
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
    // OneOf flexible spacing
    #(
      "Integer { x | x in {10, 20, 30} }",
      Ok(refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    #(
      "Integer { x | x in {10, 20, 30 } }",
      Ok(refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    #(
      "Integer { x | x in { 10, 20, 30} }",
      Ok(refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    #(
      "String { x | x in {pizza, pasta} }",
      Ok(refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.String),
        set.from_list(["pizza", "pasta"]),
      )),
    ),
    // OneOf flexible spacing - around outer brace and pipe
    #(
      "Integer {x | x in { 10, 20, 30 } }",
      Ok(refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    #(
      "Integer { x| x in { 10, 20, 30 } }",
      Ok(refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    #(
      "Integer { x |x in { 10, 20, 30 } }",
      Ok(refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    #(
      "Integer { x | x in{ 10, 20, 30 } }",
      Ok(refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    // ==== Happy Path (InclusiveRange) ====
    #(
      "Integer { x | x in ( 0..100 ) }",
      Ok(refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        "0",
        "100",
      )),
    ),
    #(
      "Integer { x | x in ( -100..-50 ) }",
      Ok(refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        "-100",
        "-50",
      )),
    ),
    #(
      "Integer { x | x in ( -10..10 ) }",
      Ok(refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        "-10",
        "10",
      )),
    ),
    #(
      "Float { x | x in ( 0.0..100.0 ) }",
      Ok(refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Float,
        )),
        "0.0",
        "100.0",
      )),
    ),
    #(
      "Float { x | x in ( -100.5..-50.5 ) }",
      Ok(refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Float,
        )),
        "-100.5",
        "-50.5",
      )),
    ),
    #(
      "Float { x | x in ( -10.5..10.5 ) }",
      Ok(refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Float,
        )),
        "-10.5",
        "10.5",
      )),
    ),
    // InclusiveRange flexible spacing
    #(
      "Integer { x | x in (0..100) }",
      Ok(refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        "0",
        "100",
      )),
    ),
    #(
      "Integer { x | x in (0..100 ) }",
      Ok(refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        "0",
        "100",
      )),
    ),
    #(
      "Integer { x | x in ( 0..100) }",
      Ok(refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        "0",
        "100",
      )),
    ),
    #(
      "Float { x | x in (0.0..100.0) }",
      Ok(refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Float,
        )),
        "0.0",
        "100.0",
      )),
    ),
    // InclusiveRange flexible spacing - around outer brace and pipe
    #(
      "Integer {x | x in ( 0..100 ) }",
      Ok(refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        "0",
        "100",
      )),
    ),
    #(
      "Integer { x| x in ( 0..100 ) }",
      Ok(refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        "0",
        "100",
      )),
    ),
    #(
      "Integer { x |x in ( 0..100 ) }",
      Ok(refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        "0",
        "100",
      )),
    ),
    #(
      "Integer { x | x in( 0..100 ) }",
      Ok(refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        "0",
        "100",
      )),
    ),
    // ==== Sad Path (OneOf) ====
    #("Boolean { x | x in { True, False } }", Error(Nil)),
    #("Integer { x | x in {  } }", Error(Nil)),
    #("Float { x | x in {  } }", Error(Nil)),
    #("String { x | x in {  } }", Error(Nil)),
    #("Integer { x | x in { 10.0 } }", Error(Nil)),
    #("Float { x | x in { pizza } }", Error(Nil)),
    #("Unknown { x | x in { 1, 2, 3 } }", Error(Nil)),
    #("List(String) { x | x in { a, b, c } }", Error(Nil)),
    #("Dict(String, String) { x | x in { a, b, c } }", Error(Nil)),
    #("Optional(String) { x | x in { a, b, c } }", Error(Nil)),
    #("Defaulted(Boolean, True) { x | x in { True, False } }", Error(Nil)),
    #("Defaulted(List(String), a) { x | x in { a, b, c } }", Error(Nil)),
    #("Defaulted(Dict(String, String), a) { x | x in { a, b } }", Error(Nil)),
    #("Defaulted(Optional(String), a) { x | x in { a, b, c } }", Error(Nil)),
    #("Integer { x | x in { 10, 20, 30 }", Error(Nil)),
    #("Integer { x | x in 10, 20, 30 } }", Error(Nil)),
    #("Integer x | x in { 10, 20, 30 } }", Error(Nil)),
    #("Integer { y | y in { 10, 20, 30 } }", Error(Nil)),
    #("Integer { x | x IN { 10, 20, 30 } }", Error(Nil)),
    #("Integer { x | xin { 10, 20, 30 } }", Error(Nil)),
    #("Integer { x | x in { 10, 10, 20 } }", Error(Nil)),
    #("String { x | x in { pizza, pizza, pasta } }", Error(Nil)),
    // ==== Sad Path (InclusiveRange) ====
    #("String { x | x in ( a..z ) }", Error(Nil)),
    #("Integer { x | x in ( 0.5..100.5 ) }", Error(Nil)),
    #("Float { x | x in ( a..z ) }", Error(Nil)),
    #("Integer { x | x in ( ..100 ) }", Error(Nil)),
    #("Integer { x | x in ( 0.. ) }", Error(Nil)),
    #("Integer { x | x in ( 0..50..100 ) }", Error(Nil)),
    #("Integer { x | x in { 0..100 } }", Error(Nil)),
    #("Integer { x | x in ( 100..0 ) }", Error(Nil)),
    #("Float { x | x in ( 100.0..0.0 ) }", Error(Nil)),
    #("Defaulted(Integer, 50) { x | x in ( 0..100 ) }", Error(Nil)),
    #("Defaulted(Float, 1.5) { x | x in ( 0.0..100.0 ) }", Error(Nil)),
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
// * ✅ InclusiveRange(T, low, high) -> "T { x | x in { (low..high ) }"
//   * ✅ Integer - basic range
//   * ✅ Integer - negative range
//   * ✅ Float - basic range
//   * ✅ Float - negative range
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
    // InclusiveRange(Integer) - basic range
    #(
      refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        "0",
        "100",
      ),
      "Integer { x | x in ( 0..100 ) }",
    ),
    // InclusiveRange(Integer) - negative range
    #(
      refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        "-100",
        "-50",
      ),
      "Integer { x | x in ( -100..-50 ) }",
    ),
    // InclusiveRange(Float) - basic range
    #(
      refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Float,
        )),
        "0.0",
        "100.0",
      ),
      "Float { x | x in ( 0.0..100.0 ) }",
    ),
    // InclusiveRange(Float) - negative range
    #(
      refinement_types.InclusiveRange(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Float,
        )),
        "-100.5",
        "-50.5",
      ),
      "Float { x | x in ( -100.5..-50.5 ) }",
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
// * ✅ InclusiveRange(Integer) - value in range
// * ✅ InclusiveRange(Integer) - value at low boundary
// * ✅ InclusiveRange(Integer) - value at high boundary
// * ✅ InclusiveRange(Integer) - value below range
// * ✅ InclusiveRange(Integer) - value above range
// * ✅ InclusiveRange(Integer) - negative range
// * ✅ InclusiveRange(Integer) - wrong type entirely -> Error
// * ✅ InclusiveRange(Float) - value in range
// * ✅ InclusiveRange(Float) - value at low boundary
// * ✅ InclusiveRange(Float) - value at high boundary
// * ✅ InclusiveRange(Float) - value below range
// * ✅ InclusiveRange(Float) - value above range
// * ✅ InclusiveRange(Float) - wrong type entirely -> Error
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
    // InclusiveRange(Integer) happy path - value in range
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          "0",
          "100",
        ),
        dynamic.int(50),
      ),
      True,
    ),
    // InclusiveRange(Integer) happy path - value at low boundary (inclusive)
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          "0",
          "100",
        ),
        dynamic.int(0),
      ),
      True,
    ),
    // InclusiveRange(Integer) happy path - value at high boundary (inclusive)
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          "0",
          "100",
        ),
        dynamic.int(100),
      ),
      True,
    ),
    // InclusiveRange(Integer) sad path - value below range
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          "0",
          "100",
        ),
        dynamic.int(-1),
      ),
      False,
    ),
    // InclusiveRange(Integer) sad path - value above range
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          "0",
          "100",
        ),
        dynamic.int(101),
      ),
      False,
    ),
    // InclusiveRange(Integer) happy path - negative range
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          "-100",
          "-50",
        ),
        dynamic.int(-75),
      ),
      True,
    ),
    // InclusiveRange(Integer) sad path - negative range, value outside
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          "-100",
          "-50",
        ),
        dynamic.int(-49),
      ),
      False,
    ),
    // InclusiveRange(Integer) sad path - wrong type entirely
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          "0",
          "100",
        ),
        dynamic.string("not an integer"),
      ),
      False,
    ),
    // InclusiveRange(Float) happy path - value in range
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Float,
          )),
          "0.0",
          "100.0",
        ),
        dynamic.float(50.5),
      ),
      True,
    ),
    // InclusiveRange(Float) happy path - value at low boundary (inclusive)
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Float,
          )),
          "0.0",
          "100.0",
        ),
        dynamic.float(0.0),
      ),
      True,
    ),
    // InclusiveRange(Float) happy path - value at high boundary (inclusive)
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Float,
          )),
          "0.0",
          "100.0",
        ),
        dynamic.float(100.0),
      ),
      True,
    ),
    // InclusiveRange(Float) sad path - value below range
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Float,
          )),
          "0.0",
          "100.0",
        ),
        dynamic.float(-0.1),
      ),
      False,
    ),
    // InclusiveRange(Float) sad path - value above range
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Float,
          )),
          "0.0",
          "100.0",
        ),
        dynamic.float(100.1),
      ),
      False,
    ),
    // InclusiveRange(Float) sad path - wrong type entirely
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Float,
          )),
          "0.0",
          "100.0",
        ),
        dynamic.string("not a float"),
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
        accepted_types.get_numeric_type,
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
// * ✅ InclusiveRange(Integer) - resolves value to string
// * ✅ InclusiveRange(Integer) - decode error returns Error
// * ✅ InclusiveRange(Float) - resolves value to string
// * ✅ InclusiveRange(Float) - decode error returns Error
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
      Error("Unable to decode OneOf refinement type value."),
    ),
    // InclusiveRange(Integer) happy path
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          "0",
          "100",
        ),
        dynamic.int(50),
      ),
      Ok("50"),
    ),
    // InclusiveRange(Integer) decode error - wrong type
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          "0",
          "100",
        ),
        dynamic.string("not an integer"),
      ),
      Error("Unable to decode InclusiveRange refinement type value."),
    ),
    // InclusiveRange(Float) happy path
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Float,
          )),
          "0.0",
          "100.0",
        ),
        dynamic.float(50.5),
      ),
      Ok("50.5"),
    ),
    // InclusiveRange(Float) decode error - wrong type
    #(
      #(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Float,
          )),
          "0.0",
          "100.0",
        ),
        dynamic.string("not a float"),
      ),
      Error("Unable to decode InclusiveRange refinement type value."),
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

// ==== all_type_metas ====
// * ✅ returns 2 entries (OneOf, InclusiveRange)
pub fn all_type_metas_test() {
  let metas = refinement_types.all_type_metas()
  list.length(metas) |> should.equal(2)

  let names = list.map(metas, fn(m) { m.name })
  list.contains(names, "OneOf") |> should.be_true()
  list.contains(names, "InclusiveRange") |> should.be_true()
}

// ==== try_each_inner ====
// * ✅ OneOf calls f with inner type
// * ✅ InclusiveRange calls f with inner type
// * ✅ Error propagation
pub fn try_each_inner_test() {
  let always_ok = fn(_: AcceptedTypes) { Ok(Nil) }
  let string_type = accepted_types.PrimitiveType(primitive_types.String)

  refinement_types.try_each_inner(
    refinement_types.OneOf(string_type, set.from_list(["a"])),
    always_ok,
  )
  |> should.equal(Ok(Nil))

  refinement_types.try_each_inner(
    refinement_types.InclusiveRange(
      accepted_types.PrimitiveType(primitive_types.NumericType(
        numeric_types.Integer,
      )),
      "0",
      "100",
    ),
    always_ok,
  )
  |> should.equal(Ok(Nil))

  let always_err = fn(_: AcceptedTypes) { Error("fail") }
  refinement_types.try_each_inner(
    refinement_types.OneOf(string_type, set.from_list(["a"])),
    always_err,
  )
  |> should.equal(Error("fail"))
}

// ==== map_inner ====
// * ✅ OneOf transforms inner, preserves set
// * ✅ InclusiveRange transforms inner, preserves bounds
pub fn map_inner_test() {
  let string_type = accepted_types.PrimitiveType(primitive_types.String)
  let bool_type = accepted_types.PrimitiveType(primitive_types.Boolean)
  let to_bool = fn(_: AcceptedTypes) { bool_type }

  refinement_types.map_inner(
    refinement_types.OneOf(string_type, set.from_list(["a", "b"])),
    to_bool,
  )
  |> should.equal(refinement_types.OneOf(bool_type, set.from_list(["a", "b"])))

  let int_type =
    accepted_types.PrimitiveType(primitive_types.NumericType(
      numeric_types.Integer,
    ))
  refinement_types.map_inner(
    refinement_types.InclusiveRange(int_type, "0", "100"),
    to_bool,
  )
  |> should.equal(refinement_types.InclusiveRange(bool_type, "0", "100"))
}

// ==== validate_default_value ====
// * ✅ OneOf - value in set -> Ok
// * ✅ OneOf - value not in set -> Error
// * ✅ InclusiveRange - value in range -> Ok
// * ✅ InclusiveRange - value out of range -> Error
pub fn validate_default_value_test() {
  let string_type = accepted_types.PrimitiveType(primitive_types.String)
  let int_type =
    accepted_types.PrimitiveType(primitive_types.NumericType(
      numeric_types.Integer,
    ))
  let validate_inner = fn(typ: AcceptedTypes, val: String) {
    case typ {
      accepted_types.PrimitiveType(primitive_types.String) -> Ok(Nil)
      accepted_types.PrimitiveType(primitive_types.NumericType(numeric)) ->
        numeric_types.validate_default_value(numeric, val)
      _ -> Error(Nil)
    }
  }

  // OneOf - value in set
  refinement_types.validate_default_value(
    refinement_types.OneOf(string_type, set.from_list(["a", "b", "c"])),
    "b",
    validate_inner,
    accepted_types.get_numeric_type,
  )
  |> should.equal(Ok(Nil))

  // OneOf - value not in set
  refinement_types.validate_default_value(
    refinement_types.OneOf(string_type, set.from_list(["a", "b", "c"])),
    "z",
    validate_inner,
    accepted_types.get_numeric_type,
  )
  |> should.equal(Error(Nil))

  // InclusiveRange - value in range
  refinement_types.validate_default_value(
    refinement_types.InclusiveRange(int_type, "0", "100"),
    "50",
    validate_inner,
    accepted_types.get_numeric_type,
  )
  |> should.equal(Ok(Nil))

  // InclusiveRange - value out of range
  refinement_types.validate_default_value(
    refinement_types.InclusiveRange(int_type, "0", "100"),
    "200",
    validate_inner,
    accepted_types.get_numeric_type,
  )
  |> should.equal(Error(Nil))
}

// ==== decode_refinement_to_string ====
// * ✅ always returns failure decoder
pub fn decode_refinement_to_string_test() {
  let string_type = accepted_types.PrimitiveType(primitive_types.String)
  let decoder =
    refinement_types.decode_refinement_to_string(
      refinement_types.OneOf(string_type, set.from_list(["a"])),
      accepted_types.decode_value_to_string,
    )
  decode.run(dynamic.string("a"), decoder)
  |> should.be_error()
}
