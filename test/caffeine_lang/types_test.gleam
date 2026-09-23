import caffeine_lang/types.{
  type ParsedType, Boolean, CollectionType, Defaulted, Dict, Float,
  InclusiveRange, Integer, List, ModifierType, NumericType, OneOf, Optional,
  ParsedCollection, ParsedModifier, ParsedPrimitive, ParsedRecord,
  ParsedRefinement, ParsedTypeAliasRef, Percentage, PrimitiveType, RecordType,
  RefinementType, SemanticType, String, URL,
}
import caffeine_lang/value
import gleam/dict
import gleam/list
import gleam/set
import gleam/string
import gleeunit/should
import test_helpers

// ===========================================================================
// NumericTypes tests
// ===========================================================================

// ==== numeric_type_to_string ====
// * ✅ Float -> "Float"
// * ✅ Integer -> "Integer"
// * ✅ Percentage -> "Percentage"
pub fn numeric_type_to_string_test() {
  [
    #("Float -> Float", Float, "Float"),
    #("Integer -> Integer", Integer, "Integer"),
    #("Percentage -> Percentage", Percentage, "Percentage"),
  ]
  |> test_helpers.table_test_1(types.numeric_type_to_string)
}

// ==== validate_numeric_value ====
// ==== Happy Path ====
// * ✅ Integer with valid int value
// * ✅ Float with valid float value
// ==== Sad Path ====
// * ✅ Integer with non-integer value
// * ✅ Float with non-float value (String only - Int/Float distinction is platform-specific)
pub fn validate_numeric_value_test() {
  let int_val = value.IntValue(42)
  let float_val = value.FloatValue(3.14)
  let string_val = value.StringValue("hello")

  // Integer validation
  [
    #("Integer with valid int value", #(Integer, int_val), Ok(int_val)),
    #(
      "Integer with string value",
      #(Integer, string_val),
      Error([types.ValidationError(expected: "Int", found: "String", path: [])]),
    ),
    #(
      "Integer with float value",
      #(Integer, float_val),
      Error([types.ValidationError(expected: "Int", found: "Float", path: [])]),
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    types.validate_numeric_value(input.0, input.1)
  })

  // Float validation
  // Note: Int -> Float validation is platform-specific (JS doesn't distinguish Int/Float)
  [
    #("Float with valid float value", #(Float, float_val), Ok(float_val)),
    #(
      "Float with string value",
      #(Float, string_val),
      Error([
        types.ValidationError(expected: "Float", found: "String", path: []),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    types.validate_numeric_value(input.0, input.1)
  })

  // Percentage validation
  let pct_ok = value.PercentageValue(99.9)
  let pct_too_high = value.PercentageValue(101.0)
  let pct_too_low = value.PercentageValue(-1.0)
  [
    #("Percentage with valid percentage", #(Percentage, pct_ok), Ok(pct_ok)),
    #(
      "Percentage at lower bound 0.0",
      #(Percentage, value.PercentageValue(0.0)),
      Ok(value.PercentageValue(0.0)),
    ),
    #(
      "Percentage at upper bound 100.0",
      #(Percentage, value.PercentageValue(100.0)),
      Ok(value.PercentageValue(100.0)),
    ),
    #(
      "Percentage too high",
      #(Percentage, pct_too_high),
      Error([
        types.ValidationError(
          expected: "Percentage (0.0 <= x <= 100.0)",
          found: "101.0",
          path: [],
        ),
      ]),
    ),
    #(
      "Percentage too low",
      #(Percentage, pct_too_low),
      Error([
        types.ValidationError(
          expected: "Percentage (0.0 <= x <= 100.0)",
          found: "-1.0",
          path: [],
        ),
      ]),
    ),
    #(
      "Percentage with float value (missing % suffix)",
      #(Percentage, value.FloatValue(99.9)),
      Error([
        types.ValidationError(
          expected: "Percentage (use % suffix, e.g. 99.9%)",
          found: "Float",
          path: [],
        ),
      ]),
    ),
    #(
      "Percentage with string value",
      #(Percentage, string_val),
      Error([
        types.ValidationError(expected: "Percentage", found: "String", path: []),
      ]),
    ),
    #(
      "Percentage with int value",
      #(Percentage, int_val),
      Error([
        types.ValidationError(expected: "Percentage", found: "Int", path: []),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    types.validate_numeric_value(input.0, input.1)
  })
}

// ==== validate_in_range ====
// ==== Happy Path ====
// * ✅ Integer value within range
// * ✅ Integer value at lower bound
// * ✅ Integer value at upper bound
// * ✅ Float value within range
// * ✅ Float value at lower bound
// * ✅ Float value at upper bound
// ==== Sad Path ====
// * ✅ Integer value out of range
// * ✅ Float value out of range
// * ✅ Invalid value string for type
pub fn validate_in_range_test() {
  // Integer - happy path
  [
    #("Integer value within range", #(Integer, "50", "0", "100"), Ok(Nil)),
    #("Integer value at lower bound", #(Integer, "0", "0", "100"), Ok(Nil)),
    #("Integer value at upper bound", #(Integer, "100", "0", "100"), Ok(Nil)),
    #("Integer negative value in range", #(Integer, "-5", "-10", "10"), Ok(Nil)),
  ]
  |> test_helpers.table_test_1(fn(input) {
    types.validate_in_range(input.0, input.1, input.2, input.3)
  })

  // Integer - sad path (out of range)
  [
    #(
      "Integer below range -1 in 0..100",
      #(Integer, "-1", "0", "100"),
      Error([
        types.ValidationError(expected: "0 <= x <= 100", found: "-1", path: []),
      ]),
    ),
    #(
      "Integer below range -20 in -10..10",
      #(Integer, "-20", "-10", "10"),
      Error([
        types.ValidationError(
          expected: "-10 <= x <= 10",
          found: "-20",
          path: [],
        ),
      ]),
    ),
    #(
      "Integer above range 101 in 0..100",
      #(Integer, "101", "0", "100"),
      Error([
        types.ValidationError(expected: "0 <= x <= 100", found: "101", path: []),
      ]),
    ),
    #(
      "Integer above range 15 in -10..10",
      #(Integer, "15", "-10", "10"),
      Error([
        types.ValidationError(expected: "-10 <= x <= 10", found: "15", path: []),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    types.validate_in_range(input.0, input.1, input.2, input.3)
  })

  // Integer - sad path (invalid value)
  [
    #(
      "Integer invalid value hello",
      #(Integer, "hello", "0", "100"),
      Error([
        types.ValidationError(expected: "Integer", found: "hello", path: []),
      ]),
    ),
    #(
      "Integer invalid value 3.14",
      #(Integer, "3.14", "0", "100"),
      Error([
        types.ValidationError(expected: "Integer", found: "3.14", path: []),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    types.validate_in_range(input.0, input.1, input.2, input.3)
  })

  // Float - happy path
  [
    #("Float value within range", #(Float, "0.5", "0.0", "1.0"), Ok(Nil)),
    #("Float value at lower bound", #(Float, "0.0", "0.0", "1.0"), Ok(Nil)),
    #("Float value at upper bound", #(Float, "1.0", "0.0", "1.0"), Ok(Nil)),
    #("Float negative value in range", #(Float, "-0.5", "-1.0", "1.0"), Ok(Nil)),
  ]
  |> test_helpers.table_test_1(fn(input) {
    types.validate_in_range(input.0, input.1, input.2, input.3)
  })

  // Float - sad path (out of range)
  [
    #(
      "Float below range -0.1 in 0.0..1.0",
      #(Float, "-0.1", "0.0", "1.0"),
      Error([
        types.ValidationError(
          expected: "0.0 <= x <= 1.0",
          found: "-0.1",
          path: [],
        ),
      ]),
    ),
    #(
      "Float above range 1.1 in 0.0..1.0",
      #(Float, "1.1", "0.0", "1.0"),
      Error([
        types.ValidationError(
          expected: "0.0 <= x <= 1.0",
          found: "1.1",
          path: [],
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    types.validate_in_range(input.0, input.1, input.2, input.3)
  })

  // Float - sad path (invalid value)
  [
    #(
      "Float invalid value hello",
      #(Float, "hello", "0.0", "1.0"),
      Error([types.ValidationError(expected: "Float", found: "hello", path: [])]),
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    types.validate_in_range(input.0, input.1, input.2, input.3)
  })
}

// ===========================================================================
// SemanticStringTypes tests
// ===========================================================================

// ==== semantic_type_to_string ====
// * ✅ URL -> "URL"
pub fn semantic_type_to_string_test() {
  [#("URL -> URL", URL, "URL")]
  |> test_helpers.table_test_1(types.semantic_type_to_string)
}

// ==== validate_semantic_value ====
// ==== Happy Path ====
// * ✅ String value with valid URL
// ==== Sad Path ====
// * ✅ String value with invalid URL
// * ✅ Non-string value
pub fn validate_semantic_value_test() {
  let valid_url = value.StringValue("https://example.com")
  let invalid_url = value.StringValue("not-a-url")
  let int_val = value.IntValue(42)

  // Valid URL
  [
    #(
      "String value with valid URL",
      #(PrimitiveType(SemanticType(URL)), valid_url),
      Ok(valid_url),
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    types.validate_value(input.0, input.1)
  })

  // Invalid URL string
  [
    #(
      "String value with invalid URL",
      #(PrimitiveType(SemanticType(URL)), invalid_url),
      Error([
        types.ValidationError(
          expected: "URL (starting with http:// or https://)",
          found: "not-a-url",
          path: [],
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    types.validate_value(input.0, input.1)
  })

  // Non-string value
  [
    #(
      "Non-string value",
      #(PrimitiveType(SemanticType(URL)), int_val),
      Error([
        types.ValidationError(expected: "String", found: "Int", path: []),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    types.validate_value(input.0, input.1)
  })
}

// ===========================================================================
// PrimitiveTypes tests
// ===========================================================================

// ==== primitive_type_to_string ====
// * ✅ Boolean -> "Boolean"
// * ✅ String -> "String"
// * ✅ delegates to numeric_types for NumericType
pub fn primitive_type_to_string_test() {
  [
    #("Boolean -> Boolean", Boolean, "Boolean"),
    #("String -> String", String, "String"),
    // Integration: delegates to numeric_types
    #("delegates to numeric_types for NumericType", NumericType(Float), "Float"),
  ]
  |> test_helpers.table_test_1(types.primitive_type_to_string)
}

// ==== validate_primitive_value ====
// * ✅ Boolean validates bool
// * ✅ String validates string
// * ✅ delegates to numeric_types for NumericType
pub fn validate_primitive_value_test() {
  [
    #(
      "Boolean validates bool",
      #(PrimitiveType(Boolean), value.BoolValue(True)),
      True,
    ),
    #(
      "Boolean rejects non-bool",
      #(PrimitiveType(Boolean), value.StringValue("not bool")),
      False,
    ),
    #(
      "String validates string",
      #(PrimitiveType(String), value.StringValue("hello")),
      True,
    ),
    #(
      "String rejects non-string",
      #(PrimitiveType(String), value.IntValue(42)),
      False,
    ),
    // Integration: delegates to numeric_types
    #(
      "delegates to numeric_types for Integer",
      #(PrimitiveType(NumericType(Integer)), value.IntValue(42)),
      True,
    ),
    #(
      "delegates to numeric_types for Float",
      #(PrimitiveType(NumericType(Float)), value.FloatValue(3.14)),
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    let #(typ, value) = input
    case types.validate_value(typ, value) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

// ==== resolve_primitive_to_string ====
// * ✅ Boolean resolves with resolver
// * ✅ String resolves with resolver
// * ✅ delegates to numeric_types for NumericType
pub fn resolve_primitive_to_string_test() {
  let resolver = fn(s) { "resolved:" <> s }

  [
    #(
      "Boolean resolves with resolver",
      #(Boolean, value.BoolValue(True)),
      "resolved:true",
    ),
    #(
      "String resolves with resolver",
      #(String, value.StringValue("hello")),
      "resolved:hello",
    ),
    // Integration: delegates to numeric_types
    #(
      "delegates to numeric_types for Integer",
      #(NumericType(Integer), value.IntValue(42)),
      "resolved:42",
    ),
    #(
      "delegates to numeric_types for Float",
      #(NumericType(Float), value.FloatValue(3.14)),
      "resolved:3.14",
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    let #(typ, value) = input
    types.resolve_primitive_to_string(typ, value, resolver)
  })
}

// ==== primitive_all_type_metas ====
// * ✅ returns non-empty list with expected type names
pub fn primitive_all_type_metas_test() {
  let metas = types.all_type_metas()
  { metas != [] } |> should.be_true()

  let names = list.map(metas, fn(m) { m.name })
  list.contains(names, "Boolean") |> should.be_true()
  list.contains(names, "String") |> should.be_true()
  list.contains(names, "Integer") |> should.be_true()
  list.contains(names, "Float") |> should.be_true()
}

// ===========================================================================
// CollectionTypes tests
// ===========================================================================

// ==== collection_type_to_string ====
// * ✅ List(T) -> "List(T)"
// * ✅ Dict(K, V) -> "Dict(K, V)"
pub fn collection_type_to_string_test() {
  [
    #(
      "List(String)",
      CollectionType(List(PrimitiveType(String))),
      "List(String)",
    ),
    #(
      "List(Integer)",
      CollectionType(List(PrimitiveType(NumericType(Integer)))),
      "List(Integer)",
    ),
    #(
      "Dict(String, String)",
      CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
      "Dict(String, String)",
    ),
    #(
      "Dict(String, Integer)",
      CollectionType(Dict(
        PrimitiveType(String),
        PrimitiveType(NumericType(Integer)),
      )),
      "Dict(String, Integer)",
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    types.accepted_type_to_string(input)
  })
}

// ==== validate_collection_value ====
// * ✅ List validates list of inner type
// * ✅ List rejects non-list
// * ✅ Dict validates dict with inner types
// * ✅ Dict rejects non-dict
pub fn validate_collection_value_test() {
  [
    // List happy path
    #(
      "List validates list of inner type",
      #(
        CollectionType(List(PrimitiveType(NumericType(Integer)))),
        value.ListValue([value.IntValue(1), value.IntValue(2)]),
      ),
      True,
    ),
    // List sad path - not a list
    #(
      "List rejects non-list",
      #(
        CollectionType(List(PrimitiveType(NumericType(Integer)))),
        value.StringValue("not a list"),
      ),
      False,
    ),
    // Dict happy path
    #(
      "Dict validates dict with inner types",
      #(
        CollectionType(Dict(
          PrimitiveType(String),
          PrimitiveType(NumericType(Integer)),
        )),
        value.DictValue(dict.from_list([#("a", value.IntValue(1))])),
      ),
      True,
    ),
    // Dict sad path - not a dict
    #(
      "Dict rejects non-dict",
      #(
        CollectionType(Dict(
          PrimitiveType(String),
          PrimitiveType(NumericType(Integer)),
        )),
        value.StringValue("not a dict"),
      ),
      False,
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    let #(typ, value) = input
    case types.validate_value(typ, value) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

// ==== resolve_collection_to_string ====
// * ✅ List resolves with list resolver
// * ✅ Dict returns error (unsupported)
pub fn resolve_collection_to_string_test() {
  let string_resolver = fn(s) { s }
  let list_resolver = fn(l) { "list:[" <> string.join(l, ",") <> "]" }

  [
    // List happy path
    #(
      "List resolves with list resolver",
      #(
        CollectionType(List(PrimitiveType(String))),
        value.ListValue([value.StringValue("a"), value.StringValue("b")]),
      ),
      Ok("list:[a,b]"),
    ),
    // Dict returns error
    #(
      "Dict returns error (unsupported)",
      #(
        CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
        value.ListValue([]),
      ),
      Error(
        "Unsupported templatized variable type: Dict(String, String). Dict support is pending, open an issue if this is a desired use case.",
      ),
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    let #(typ, value) = input
    types.resolve_to_string(typ, value, string_resolver, list_resolver)
  })
}

// ==== collection_all_type_metas ====
// * ✅ returns entries for List and Dict
pub fn collection_all_type_metas_test() {
  let metas = types.all_type_metas()
  let names = list.map(metas, fn(m) { m.name })
  list.contains(names, "List") |> should.be_true()
  list.contains(names, "Dict") |> should.be_true()
}

// ===========================================================================
// ModifierTypes tests
// ===========================================================================

// ==== modifier_type_to_string ====
// * ✅ Optional(T) -> "Optional(T)"
// * ✅ Defaulted(T, val) -> "Defaulted(T, val)"
pub fn modifier_type_to_string_test() {
  [
    #(
      "Optional(String)",
      ModifierType(Optional(PrimitiveType(String))),
      "Optional(String)",
    ),
    #(
      "Optional(Integer)",
      ModifierType(Optional(PrimitiveType(NumericType(Integer)))),
      "Optional(Integer)",
    ),
    #(
      "Defaulted(String, hello)",
      ModifierType(Defaulted(PrimitiveType(String), "hello")),
      "Defaulted(String, hello)",
    ),
    #(
      "Defaulted(Integer, 10)",
      ModifierType(Defaulted(PrimitiveType(NumericType(Integer)), "10")),
      "Defaulted(Integer, 10)",
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    types.accepted_type_to_string(input)
  })
}

// ==== validate_modifier_value ====
// ==== Optional ====
// * ✅ Optional with value present validates inner type
// * ✅ Optional with value absent (None) succeeds
// ==== Defaulted ====
// * ✅ Defaulted with value present validates inner type
// * ✅ Defaulted with value absent (None) succeeds
pub fn validate_modifier_value_test() {
  [
    // Optional with value present
    #(
      "Optional with value present validates inner type",
      #(
        ModifierType(Optional(PrimitiveType(String))),
        value.StringValue("hello"),
      ),
      True,
    ),
    // Optional with None
    #(
      "Optional with value absent (None) succeeds",
      #(ModifierType(Optional(PrimitiveType(String))), value.NilValue),
      True,
    ),
    // Defaulted with value present
    #(
      "Defaulted with value present validates inner type",
      #(
        ModifierType(Defaulted(PrimitiveType(String), "default")),
        value.StringValue("custom"),
      ),
      True,
    ),
    // Defaulted with None
    #(
      "Defaulted with value absent (None) succeeds",
      #(
        ModifierType(Defaulted(PrimitiveType(String), "default")),
        value.NilValue,
      ),
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    let #(typ, value) = input
    case types.validate_value(typ, value) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

// ==== resolve_modifier_to_string ====
// ==== Optional ====
// * ✅ Optional with value present resolves inner value
// * ✅ Optional with None returns empty string
// ==== Defaulted ====
// * ✅ Defaulted with value present resolves inner value
// * ✅ Defaulted with None uses default value
pub fn resolve_modifier_to_string_test() {
  let resolve_string = fn(s) { "resolved:" <> s }
  let resolve_list = fn(l) { string.join(l, ",") }

  [
    // Optional with value present
    #(
      "Optional with value present resolves inner value",
      #(
        ModifierType(Optional(PrimitiveType(String))),
        value.StringValue("hello"),
      ),
      Ok("resolved:hello"),
    ),
    // Optional with None returns empty string
    #(
      "Optional with None returns empty string",
      #(ModifierType(Optional(PrimitiveType(String))), value.NilValue),
      Ok(""),
    ),
    // Defaulted with value present
    #(
      "Defaulted with value present resolves inner value",
      #(
        ModifierType(Defaulted(PrimitiveType(String), "default")),
        value.StringValue("custom"),
      ),
      Ok("resolved:custom"),
    ),
    // Defaulted with None uses default
    #(
      "Defaulted with None uses default value",
      #(
        ModifierType(Defaulted(PrimitiveType(String), "default")),
        value.NilValue,
      ),
      Ok("resolved:default"),
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    let #(typ, value) = input
    types.resolve_to_string(typ, value, resolve_string, resolve_list)
    |> result_to_ok_string_from_string_error
  })
}

// ==== modifier_all_type_metas ====
// * ✅ returns entries for Optional and Defaulted
pub fn modifier_all_type_metas_test() {
  let metas = types.all_type_metas()
  let names = list.map(metas, fn(m) { m.name })
  list.contains(names, "Optional") |> should.be_true()
  list.contains(names, "Defaulted") |> should.be_true()
}

// ===========================================================================
// RefinementTypes tests
// ===========================================================================

// ==== refinement_type_to_string ====
pub fn refinement_type_to_string_test() {
  [
    #(
      "OneOf Integer set",
      RefinementType(OneOf(
        PrimitiveType(NumericType(Integer)),
        set.from_list(["10", "20", "30"]),
      )),
      "Integer { x | x in { 10, 20, 30 } }",
    ),
    #(
      "OneOf Float set",
      RefinementType(OneOf(
        PrimitiveType(NumericType(Float)),
        set.from_list(["10.0", "20.0", "30.0"]),
      )),
      "Float { x | x in { 10.0, 20.0, 30.0 } }",
    ),
    #(
      "OneOf String set",
      RefinementType(OneOf(
        PrimitiveType(String),
        set.from_list(["pasta", "pizza", "salad"]),
      )),
      "String { x | x in { pasta, pizza, salad } }",
    ),
    #(
      "OneOf Defaulted(String) set",
      RefinementType(OneOf(
        ModifierType(Defaulted(PrimitiveType(String), "default")),
        set.from_list(["a", "b", "c"]),
      )),
      "Defaulted(String, default) { x | x in { a, b, c } }",
    ),
    #(
      "OneOf Defaulted(Integer) set",
      RefinementType(OneOf(
        ModifierType(Defaulted(PrimitiveType(NumericType(Integer)), "10")),
        set.from_list(["10", "20", "30"]),
      )),
      "Defaulted(Integer, 10) { x | x in { 10, 20, 30 } }",
    ),
    // InclusiveRange(Integer) - basic range
    #(
      "InclusiveRange Integer basic range",
      RefinementType(InclusiveRange(
        PrimitiveType(NumericType(Integer)),
        "0",
        "100",
      )),
      "Integer { x | x in ( 0..100 ) }",
    ),
    // InclusiveRange(Integer) - negative range
    #(
      "InclusiveRange Integer negative range",
      RefinementType(InclusiveRange(
        PrimitiveType(NumericType(Integer)),
        "-100",
        "-50",
      )),
      "Integer { x | x in ( -100..-50 ) }",
    ),
    // InclusiveRange(Float) - basic range
    #(
      "InclusiveRange Float basic range",
      RefinementType(InclusiveRange(
        PrimitiveType(NumericType(Float)),
        "0.0",
        "100.0",
      )),
      "Float { x | x in ( 0.0..100.0 ) }",
    ),
    // InclusiveRange(Float) - negative range
    #(
      "InclusiveRange Float negative range",
      RefinementType(InclusiveRange(
        PrimitiveType(NumericType(Float)),
        "-100.5",
        "-50.5",
      )),
      "Float { x | x in ( -100.5..-50.5 ) }",
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    types.accepted_type_to_string(input)
  })
}

// ==== validate_refinement_value ====
pub fn validate_refinement_value_test() {
  [
    // Integer happy path - value in set
    #(
      "Integer value in set",
      #(
        RefinementType(OneOf(
          PrimitiveType(NumericType(Integer)),
          set.from_list(["10", "20", "30"]),
        )),
        value.IntValue(10),
      ),
      True,
    ),
    // Integer sad path - value not in set
    #(
      "Integer value not in set",
      #(
        RefinementType(OneOf(
          PrimitiveType(NumericType(Integer)),
          set.from_list(["10", "20", "30"]),
        )),
        value.IntValue(99),
      ),
      False,
    ),
    // String happy path - value in set
    #(
      "String value in set",
      #(
        RefinementType(OneOf(
          PrimitiveType(String),
          set.from_list(["pizza", "pasta", "salad"]),
        )),
        value.StringValue("pizza"),
      ),
      True,
    ),
    // String sad path - value not in set
    #(
      "String value not in set",
      #(
        RefinementType(OneOf(
          PrimitiveType(String),
          set.from_list(["pizza", "pasta", "salad"]),
        )),
        value.StringValue("burger"),
      ),
      False,
    ),
    // InclusiveRange(Integer) happy path - value in range
    #(
      "InclusiveRange Integer value in range",
      #(
        RefinementType(InclusiveRange(
          PrimitiveType(NumericType(Integer)),
          "0",
          "100",
        )),
        value.IntValue(50),
      ),
      True,
    ),
    // InclusiveRange(Integer) sad path - value below range
    #(
      "InclusiveRange Integer value below range",
      #(
        RefinementType(InclusiveRange(
          PrimitiveType(NumericType(Integer)),
          "0",
          "100",
        )),
        value.IntValue(-1),
      ),
      False,
    ),
    // InclusiveRange(Float) happy path - value in range
    #(
      "InclusiveRange Float value in range",
      #(
        RefinementType(InclusiveRange(
          PrimitiveType(NumericType(Float)),
          "0.0",
          "100.0",
        )),
        value.FloatValue(50.5),
      ),
      True,
    ),
    // InclusiveRange(Float) sad path - value above range
    #(
      "InclusiveRange Float value above range",
      #(
        RefinementType(InclusiveRange(
          PrimitiveType(NumericType(Float)),
          "0.0",
          "100.0",
        )),
        value.FloatValue(100.1),
      ),
      False,
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    let #(typ, value) = input
    case types.validate_value(typ, value) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

// ==== resolve_refinement_to_string ====
pub fn resolve_refinement_to_string_test() {
  let resolve_string = fn(x: String) { x }
  let resolve_list = fn(l) { string.join(l, ",") }

  [
    // Integer happy path
    #(
      "Integer OneOf resolves value",
      #(
        RefinementType(OneOf(
          PrimitiveType(NumericType(Integer)),
          set.from_list(["10", "20", "30"]),
        )),
        value.IntValue(10),
      ),
      Ok("10"),
    ),
    // String happy path
    #(
      "String OneOf resolves value",
      #(
        RefinementType(OneOf(
          PrimitiveType(String),
          set.from_list(["pasta", "pizza", "salad"]),
        )),
        value.StringValue("pizza"),
      ),
      Ok("pizza"),
    ),
    // Decode error - wrong type
    #(
      "OneOf decode error - wrong type",
      #(
        RefinementType(OneOf(
          PrimitiveType(NumericType(Integer)),
          set.from_list(["10", "20", "30"]),
        )),
        value.StringValue("not an integer"),
      ),
      Error("Unable to resolve OneOf refinement type value."),
    ),
    // InclusiveRange(Integer) happy path
    #(
      "InclusiveRange Integer resolves value",
      #(
        RefinementType(InclusiveRange(
          PrimitiveType(NumericType(Integer)),
          "0",
          "100",
        )),
        value.IntValue(50),
      ),
      Ok("50"),
    ),
    // InclusiveRange(Integer) decode error
    #(
      "InclusiveRange decode error - wrong type",
      #(
        RefinementType(InclusiveRange(
          PrimitiveType(NumericType(Integer)),
          "0",
          "100",
        )),
        value.StringValue("not an integer"),
      ),
      Error("Unable to resolve InclusiveRange refinement type value."),
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    let #(typ, value) = input
    types.resolve_to_string(typ, value, resolve_string, resolve_list)
  })
}

// ==== refinement_all_type_metas ====
// * ✅ returns entries for OneOf and InclusiveRange
pub fn refinement_all_type_metas_test() {
  let metas = types.all_type_metas()
  let names = list.map(metas, fn(m) { m.name })
  list.contains(names, "OneOf") |> should.be_true()
  list.contains(names, "InclusiveRange") |> should.be_true()
}

// ===========================================================================
// AcceptedTypes (integration) tests
// ===========================================================================

// ==== accepted_type_to_string ====
// Integration test: verifies dispatch across type hierarchy
// * ✅ Primitive -> delegates to primitive_types
// * ✅ Collection -> delegates to collection_types
// * ✅ Modifier wrapping Collection -> nested delegation
pub fn accepted_type_to_string_test() {
  [
    // Primitive dispatch
    #("Primitive delegates to primitive_types", PrimitiveType(String), "String"),
    // Collection dispatch
    #(
      "Collection delegates to collection_types",
      CollectionType(List(PrimitiveType(String))),
      "List(String)",
    ),
    // Modifier wrapping Collection - nested dispatch
    #(
      "Modifier wrapping Collection - nested delegation",
      ModifierType(
        Optional(
          CollectionType(Dict(
            PrimitiveType(String),
            PrimitiveType(NumericType(Integer)),
          )),
        ),
      ),
      "Optional(Dict(String, Integer))",
    ),
  ]
  |> test_helpers.table_test_1(types.accepted_type_to_string)
}

// ==== validate_value (integration) ====
// * ✅ Primitive dispatch
// * ✅ Collection dispatch
// * ✅ Modifier dispatch
// * ✅ Refinement dispatch
// * ✅ Record dispatch
pub fn validate_value_test() {
  [
    // Primitive dispatch
    #(
      "Primitive dispatch",
      #(PrimitiveType(String), value.StringValue("hello")),
      True,
    ),
    // Collection dispatch
    #(
      "Collection dispatch",
      #(
        CollectionType(List(PrimitiveType(NumericType(Integer)))),
        value.ListValue([value.IntValue(1), value.IntValue(2)]),
      ),
      True,
    ),
    // Modifier dispatch
    #(
      "Modifier dispatch",
      #(ModifierType(Optional(PrimitiveType(String))), value.NilValue),
      True,
    ),
    // Refinement dispatch
    #(
      "Refinement dispatch",
      #(
        RefinementType(OneOf(PrimitiveType(String), set.from_list(["a", "b"]))),
        value.StringValue("a"),
      ),
      True,
    ),
    // Record dispatch
    #(
      "Record dispatch",
      #(
        RecordType(
          dict.from_list([
            #("name", PrimitiveType(String)),
            #("count", PrimitiveType(NumericType(Integer))),
          ]),
        ),
        value.DictValue(
          dict.from_list([
            #("name", value.StringValue("test")),
            #("count", value.IntValue(42)),
          ]),
        ),
      ),
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    let #(typ, value) = input
    case types.validate_value(typ, value) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

fn result_to_ok_string_from_string_error(
  result: Result(String, String),
) -> Result(String, Nil) {
  case result {
    Ok(s) -> Ok(s)
    Error(_) -> Error(Nil)
  }
}

// ==== resolve_to_string (integration) ====
pub fn resolve_to_string_test() {
  let string_resolver = fn(s) { "resolved:" <> s }
  let list_resolver = fn(l) { "list:[" <> string.join(l, ",") <> "]" }

  [
    // Primitive dispatch
    #(
      "Primitive dispatch",
      #(PrimitiveType(String), value.StringValue("hello")),
      Ok("resolved:hello"),
    ),
    // Collection dispatch
    #(
      "Collection dispatch",
      #(
        CollectionType(List(PrimitiveType(NumericType(Integer)))),
        value.ListValue([value.IntValue(1), value.IntValue(2)]),
      ),
      Ok("list:[1,2]"),
    ),
    // Modifier dispatch - Optional with value
    #(
      "Modifier dispatch - Optional with value",
      #(
        ModifierType(Optional(PrimitiveType(String))),
        value.StringValue("present"),
      ),
      Ok("resolved:present"),
    ),
    // Modifier dispatch - Defaulted with None uses default
    #(
      "Modifier dispatch - Defaulted with None uses default",
      #(
        ModifierType(Defaulted(PrimitiveType(NumericType(Integer)), "99")),
        value.NilValue,
      ),
      Ok("resolved:99"),
    ),
    // Refinement dispatch - OneOf(Defaulted(String)) with value provided
    #(
      "Refinement dispatch - OneOf(Defaulted(String)) with value",
      #(
        RefinementType(OneOf(
          ModifierType(Defaulted(PrimitiveType(String), "production")),
          set.from_list(["production", "staging"]),
        )),
        value.StringValue("staging"),
      ),
      Ok("resolved:staging"),
    ),
    // Refinement dispatch - OneOf(Defaulted(String)) with None uses default
    #(
      "Refinement dispatch - OneOf(Defaulted(String)) with None uses default",
      #(
        RefinementType(OneOf(
          ModifierType(Defaulted(PrimitiveType(String), "production")),
          set.from_list(["production", "staging"]),
        )),
        value.NilValue,
      ),
      Ok("resolved:production"),
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    let #(typ, value) = input
    types.resolve_to_string(typ, value, string_resolver, list_resolver)
    |> result_to_ok_string_from_string_error
  })
}

// ==== get_numeric_type ====
// * ✅ Integer primitive -> Integer
// * ✅ Float primitive -> Float
// * ✅ Non-numeric types fall back to Integer
pub fn get_numeric_type_test() {
  [
    #(
      "Integer primitive -> Integer",
      PrimitiveType(NumericType(Integer)),
      Integer,
    ),
    #("Float primitive -> Float", PrimitiveType(NumericType(Float)), Float),
    // Fallback cases
    #("String falls back to Integer", PrimitiveType(String), Integer),
    #("Boolean falls back to Integer", PrimitiveType(Boolean), Integer),
    #(
      "Collection falls back to Integer",
      CollectionType(List(PrimitiveType(String))),
      Integer,
    ),
  ]
  |> test_helpers.table_test_1(types.get_numeric_type)
}

// ==== is_optional_or_defaulted ====
// * ✅ Optional -> True
// * ✅ Defaulted -> True
// * ✅ OneOf wrapping Optional -> True
// * ✅ Plain primitive -> False
// * ✅ Collection -> False
pub fn is_optional_or_defaulted_test() {
  [
    #("Optional -> True", ModifierType(Optional(PrimitiveType(String))), True),
    #(
      "Defaulted -> True",
      ModifierType(Defaulted(PrimitiveType(String), "hello")),
      True,
    ),
    #(
      "OneOf wrapping Optional -> True",
      RefinementType(OneOf(
        ModifierType(Optional(PrimitiveType(String))),
        set.from_list(["a", "b"]),
      )),
      True,
    ),
    #("Plain primitive -> False", PrimitiveType(String), False),
    #("Collection -> False", CollectionType(List(PrimitiveType(String))), False),
  ]
  |> test_helpers.table_test_1(types.is_optional_or_defaulted)
}

// ==== all_type_metas ====
// * ✅ returns non-empty list with entries from all 5 categories
pub fn all_type_metas_test() {
  let metas = types.all_type_metas()
  // Should have entries from primitives, collections, structured, modifiers, and refinements
  { metas != [] } |> should.be_true()

  // Verify it includes entries from each category by checking known names
  let names = list.map(metas, fn(m) { m.name })
  list.contains(names, "Boolean") |> should.be_true()
  list.contains(names, "List") |> should.be_true()
  list.contains(names, "Optional") |> should.be_true()
  list.contains(names, "OneOf") |> should.be_true()
}

// ==== completable_type_metas ====
// * ✅ includes primitives, collections, and modifiers
// * ✅ excludes refinement types (OneOf, InclusiveRange)
pub fn completable_type_metas_test() {
  let metas = types.completable_type_metas()
  let names = list.map(metas, fn(m) { m.name })

  // Includes completable types
  list.contains(names, "Boolean") |> should.be_true()
  list.contains(names, "List") |> should.be_true()
  list.contains(names, "Optional") |> should.be_true()

  // Excludes refinement types — they are not standalone types
  list.contains(names, "OneOf") |> should.be_false()
  list.contains(names, "InclusiveRange") |> should.be_false()
}

// ===========================================================================
// RecordType tests
// ===========================================================================

// ==== record_type_to_string ====
// * ✅ formats fields alphabetically
// * ✅ handles nested types
pub fn record_type_to_string_test() {
  // Simple record
  RecordType(
    dict.from_list([
      #("numerator", PrimitiveType(String)),
      #("denominator", PrimitiveType(String)),
    ]),
  )
  |> types.accepted_type_to_string
  |> should.equal("{ denominator: String, numerator: String }")

  // Record with mixed types
  RecordType(
    dict.from_list([
      #("name", PrimitiveType(String)),
      #("count", PrimitiveType(NumericType(Integer))),
    ]),
  )
  |> types.accepted_type_to_string
  |> should.equal("{ count: Integer, name: String }")
}

// ==== validate_record_value ====
// ==== Happy Path ====
// * ✅ all fields present and valid
// * ✅ optional field absent
// ==== Sad Path ====
// * ✅ missing required field
// * ✅ extra field rejected
// * ✅ wrong type in field
// * ✅ not a dict value
pub fn validate_record_value_test() {
  let schema =
    RecordType(
      dict.from_list([
        #("name", PrimitiveType(String)),
        #("count", PrimitiveType(NumericType(Integer))),
      ]),
    )

  // Happy: all fields present
  let val =
    value.DictValue(
      dict.from_list([
        #("name", value.StringValue("test")),
        #("count", value.IntValue(42)),
      ]),
    )
  types.validate_value(schema, val) |> should.be_ok

  // Sad: missing required field
  let missing_val =
    value.DictValue(dict.from_list([#("name", value.StringValue("test"))]))
  types.validate_value(schema, missing_val) |> should.be_error

  // Sad: extra field
  let extra_val =
    value.DictValue(
      dict.from_list([
        #("name", value.StringValue("test")),
        #("count", value.IntValue(42)),
        #("extra", value.StringValue("oops")),
      ]),
    )
  types.validate_value(schema, extra_val) |> should.be_error

  // Sad: wrong type
  let wrong_val =
    value.DictValue(
      dict.from_list([
        #("name", value.StringValue("test")),
        #("count", value.StringValue("not_an_int")),
      ]),
    )
  types.validate_value(schema, wrong_val) |> should.be_error

  // Sad: not a dict
  types.validate_value(schema, value.StringValue("nope")) |> should.be_error
}

// ==== validate_record_value (optional fields) ====
// * ✅ optional field can be absent
pub fn validate_record_value_optional_test() {
  let schema =
    RecordType(
      dict.from_list([
        #("name", PrimitiveType(String)),
        #("label", ModifierType(Optional(PrimitiveType(String)))),
      ]),
    )

  // Only required field present
  let val =
    value.DictValue(dict.from_list([#("name", value.StringValue("test"))]))
  types.validate_value(schema, val) |> should.be_ok

  // Both fields present
  let full_val =
    value.DictValue(
      dict.from_list([
        #("name", value.StringValue("test")),
        #("label", value.StringValue("my-label")),
      ]),
    )
  types.validate_value(schema, full_val) |> should.be_ok
}

// ==== validate_record_value (nested) ====
// * ✅ nested record validates recursively
pub fn validate_record_value_nested_test() {
  let schema =
    RecordType(
      dict.from_list([
        #("name", PrimitiveType(String)),
        #(
          "metrics",
          RecordType(
            dict.from_list([
              #("latency", PrimitiveType(NumericType(Integer))),
              #("errors", PrimitiveType(NumericType(Integer))),
            ]),
          ),
        ),
      ]),
    )

  let val =
    value.DictValue(
      dict.from_list([
        #("name", value.StringValue("test")),
        #(
          "metrics",
          value.DictValue(
            dict.from_list([
              #("latency", value.IntValue(100)),
              #("errors", value.IntValue(5)),
            ]),
          ),
        ),
      ]),
    )
  types.validate_value(schema, val) |> should.be_ok
}

// ==== record resolve_to_string ====
// * ✅ record types cannot be template variables
pub fn record_resolve_to_string_test() {
  let record = RecordType(dict.from_list([#("a", PrimitiveType(String))]))
  types.resolve_to_string(record, value.StringValue("x"), fn(s) { s }, fn(l) {
    string.join(l, ",")
  })
  |> should.be_error
}

// ==== record is_optional_or_defaulted ====
// * ✅ record is not optional/defaulted
pub fn record_is_optional_or_defaulted_test() {
  RecordType(dict.from_list([#("a", PrimitiveType(String))]))
  |> types.is_optional_or_defaulted
  |> should.be_false
}

// ===========================================================================
// ParsedType tests
// ===========================================================================

// ==== parsed_type_to_string ====
// * ✅ ParsedPrimitive(String) → "String"
// * ✅ ParsedPrimitive(NumericType(Integer)) → "Integer"
// * ✅ ParsedCollection(List) → "List(String)"
// * ✅ ParsedCollection(Dict) → "Dict(String, Integer)"
// * ✅ ParsedModifier(Optional) → "Optional(String)"
// * ✅ ParsedModifier(Defaulted) → "Defaulted(Float, 0.5)"
// * ✅ ParsedRefinement(OneOf) → refinement string
// * ✅ ParsedRefinement(InclusiveRange) → range string
// * ✅ ParsedTypeAliasRef → alias name directly
// * ✅ ParsedRecord → formatted record
pub fn parsed_type_to_string_test() {
  [
    #("ParsedPrimitive String", ParsedPrimitive(String), "String"),
    #(
      "ParsedPrimitive Integer",
      ParsedPrimitive(NumericType(Integer)),
      "Integer",
    ),
    #(
      "ParsedCollection List",
      ParsedCollection(List(ParsedPrimitive(String))),
      "List(String)",
    ),
    #(
      "ParsedCollection Dict",
      ParsedCollection(Dict(
        ParsedPrimitive(String),
        ParsedPrimitive(NumericType(Integer)),
      )),
      "Dict(String, Integer)",
    ),
    #(
      "ParsedModifier Optional",
      ParsedModifier(Optional(ParsedPrimitive(String))),
      "Optional(String)",
    ),
    #(
      "ParsedModifier Defaulted",
      ParsedModifier(Defaulted(ParsedPrimitive(NumericType(Float)), "0.5")),
      "Defaulted(Float, 0.5)",
    ),
    #(
      "ParsedRefinement OneOf",
      ParsedRefinement(OneOf(ParsedPrimitive(String), set.from_list(["a", "b"]))),
      "String { x | x in { a, b } }",
    ),
    #(
      "ParsedRefinement InclusiveRange",
      ParsedRefinement(InclusiveRange(
        ParsedPrimitive(NumericType(Integer)),
        "0",
        "100",
      )),
      "Integer { x | x in ( 0..100 ) }",
    ),
    #("ParsedTypeAliasRef", ParsedTypeAliasRef("_env"), "_env"),
    #(
      "ParsedRecord",
      ParsedRecord(
        dict.from_list([
          #("name", ParsedPrimitive(String)),
          #("count", ParsedPrimitive(NumericType(Integer))),
        ]),
      ),
      "{ count: Integer, name: String }",
    ),
  ]
  |> test_helpers.table_test_1(types.parsed_type_to_string)
}

// ==== try_each_inner_parsed ====
// * ✅ ParsedPrimitive calls f on self
// * ✅ ParsedTypeAliasRef calls f on self
// * ✅ ParsedCollection(List) calls f on inner type
// * ✅ ParsedModifier(Optional) calls f on inner type
// * ✅ ParsedRefinement(OneOf) calls f on inner type
// * ✅ ParsedRecord calls f on each field type
// * ✅ Error propagation through ParsedTypeAliasRef
pub fn try_each_inner_parsed_test() {
  let always_ok = fn(_: ParsedType) { Ok(Nil) }

  // ParsedPrimitive calls f on self
  types.try_each_inner_parsed(ParsedPrimitive(String), always_ok)
  |> should.equal(Ok(Nil))

  // ParsedTypeAliasRef calls f on self
  types.try_each_inner_parsed(ParsedTypeAliasRef("_env"), always_ok)
  |> should.equal(Ok(Nil))

  // ParsedCollection(List) calls f on inner
  types.try_each_inner_parsed(
    ParsedCollection(List(ParsedPrimitive(String))),
    always_ok,
  )
  |> should.equal(Ok(Nil))

  // ParsedModifier(Optional) calls f on inner
  types.try_each_inner_parsed(
    ParsedModifier(Optional(ParsedPrimitive(String))),
    always_ok,
  )
  |> should.equal(Ok(Nil))

  // ParsedRefinement(OneOf) calls f on inner
  types.try_each_inner_parsed(
    ParsedRefinement(OneOf(ParsedPrimitive(String), set.from_list(["a"]))),
    always_ok,
  )
  |> should.equal(Ok(Nil))

  // ParsedRecord calls f on each field type
  types.try_each_inner_parsed(
    ParsedRecord(
      dict.from_list([
        #("a", ParsedPrimitive(String)),
        #("b", ParsedPrimitive(NumericType(Integer))),
      ]),
    ),
    always_ok,
  )
  |> should.equal(Ok(Nil))

  // Error propagation
  let always_err = fn(_: ParsedType) { Error("fail") }
  types.try_each_inner_parsed(ParsedTypeAliasRef("_env"), always_err)
  |> should.equal(Error("fail"))
}
