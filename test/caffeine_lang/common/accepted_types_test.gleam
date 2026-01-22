import caffeine_lang/common/accepted_types
import caffeine_lang/common/collection_types
import caffeine_lang/common/modifier_types
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/common/refinement_types
import gleam/dynamic
import gleam/dynamic/decode
import gleam/set
import gleam/string
import test_helpers

// ==== accepted_type_to_string ====
// Integration test: verifies dispatch across type hierarchy
// * ✅ Primitive -> delegates to primitive_types
// * ✅ Collection -> delegates to collection_types
// * ✅ Modifier wrapping Collection -> nested delegation
pub fn accepted_type_to_string_test() {
  [
    // Primitive dispatch
    #(accepted_types.PrimitiveType(primitive_types.String), "String"),
    // Collection dispatch
    #(
      accepted_types.CollectionType(
        collection_types.List(accepted_types.PrimitiveType(
          primitive_types.String,
        )),
      ),
      "List(String)",
    ),
    // Modifier wrapping Collection - nested dispatch
    #(
      accepted_types.ModifierType(
        modifier_types.Optional(
          accepted_types.CollectionType(collection_types.Dict(
            accepted_types.PrimitiveType(primitive_types.String),
            accepted_types.PrimitiveType(primitive_types.NumericType(
              numeric_types.Integer,
            )),
          )),
        ),
      ),
      "Optional(Dict(String, Integer))",
    ),
  ]
  |> test_helpers.array_based_test_executor_1(
    accepted_types.accepted_type_to_string,
  )
}

// ==== parse_accepted_type ====
// Integration test: verifies parsing dispatch and composition rules
// * ✅ Composite: Optional(List(String)) - modifier wrapping collection
// * ✅ Nested collections: List(List(String)), Dict(String, List(String))
// * ✅ Invalid: nested modifiers not allowed
// * ✅ Invalid: Defaulted only allows primitives
// * ✅ Refinement with Defaulted inner: parses as RefinementType, not ModifierType
pub fn parse_accepted_type_test() {
  [
    // Composite type - modifier wrapping collection
    #(
      "Optional(List(String))",
      Ok(
        accepted_types.ModifierType(
          modifier_types.Optional(
            accepted_types.CollectionType(
              collection_types.List(accepted_types.PrimitiveType(
                primitive_types.String,
              )),
            ),
          ),
        ),
      ),
    ),
    // Nested collections - now allowed
    #(
      "List(List(String))",
      Ok(
        accepted_types.CollectionType(
          collection_types.List(
            accepted_types.CollectionType(
              collection_types.List(accepted_types.PrimitiveType(
                primitive_types.String,
              )),
            ),
          ),
        ),
      ),
    ),
    #(
      "Dict(String, List(String))",
      Ok(
        accepted_types.CollectionType(collection_types.Dict(
          accepted_types.PrimitiveType(primitive_types.String),
          accepted_types.CollectionType(
            collection_types.List(accepted_types.PrimitiveType(
              primitive_types.String,
            )),
          ),
        )),
      ),
    ),
    // Invalid - nested modifiers not allowed
    #("Optional(Optional(String))", Error(Nil)),
    #("Defaulted(Optional(String), default)", Error(Nil)),
    // Invalid - Defaulted only allows primitives
    #("Defaulted(List(String), default)", Error(Nil)),
    // Refinement type with Defaulted inner type - should parse as RefinementType, not ModifierType
    #(
      "Defaulted(String, production) { x | x in { production } }",
      Ok(
        accepted_types.RefinementType(refinement_types.OneOf(
          accepted_types.ModifierType(modifier_types.Defaulted(
            accepted_types.PrimitiveType(primitive_types.String),
            "production",
          )),
          set.from_list(["production"]),
        )),
      ),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(
    accepted_types.parse_accepted_type,
  )
}

// ==== validate_value ====
// Integration test: verifies validation dispatch across type hierarchy
// * ✅ Primitive -> delegates to primitive_types
// * ✅ Collection -> delegates to collection_types
// * ✅ Modifier -> delegates to modifier_types
pub fn validate_value_test() {
  [
    // Primitive dispatch
    #(
      #(
        accepted_types.PrimitiveType(primitive_types.String),
        dynamic.string("hello"),
      ),
      True,
    ),
    // Collection dispatch
    #(
      #(
        accepted_types.CollectionType(
          collection_types.List(
            accepted_types.PrimitiveType(primitive_types.NumericType(
              numeric_types.Integer,
            )),
          ),
        ),
        dynamic.list([dynamic.int(1), dynamic.int(2)]),
      ),
      True,
    ),
    // Modifier dispatch
    #(
      #(
        accepted_types.ModifierType(
          modifier_types.Optional(accepted_types.PrimitiveType(
            primitive_types.String,
          )),
        ),
        dynamic.nil(),
      ),
      True,
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    case accepted_types.validate_value(typ, value) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

// ==== decode_value_to_string ====
// Integration test: verifies decoding dispatch across type hierarchy
// * ✅ Primitive -> delegates to primitive_types
// * ✅ Modifier -> delegates to modifier_types (with inner type dispatch)
pub fn decode_value_to_string_test() {
  [
    // Primitive dispatch
    #(
      #(
        accepted_types.PrimitiveType(primitive_types.String),
        dynamic.string("hello"),
      ),
      Ok("hello"),
    ),
    // Modifier dispatch (Optional with value)
    #(
      #(
        accepted_types.ModifierType(
          modifier_types.Optional(accepted_types.PrimitiveType(
            primitive_types.String,
          )),
        ),
        dynamic.string("present"),
      ),
      Ok("present"),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    decode.run(value, accepted_types.decode_value_to_string(typ))
    |> result_to_ok_string
  })
}

fn result_to_ok_string(
  result: Result(String, List(decode.DecodeError)),
) -> Result(String, Nil) {
  case result {
    Ok(s) -> Ok(s)
    Error(_) -> Error(Nil)
  }
}

// ==== resolve_to_string ====
// Integration test: verifies resolution dispatch across type hierarchy
// * ✅ Primitive -> delegates to primitive_types
// * ✅ Collection (List) -> delegates to collection_types
// * ✅ Modifier (Optional with value) -> unwraps and delegates
// * ✅ Modifier (Defaulted with None) -> uses default
// * ✅ Refinement (OneOf with Defaulted inner, value provided) -> resolves value
// * ✅ Refinement (OneOf with Defaulted inner, None) -> uses default
pub fn resolve_to_string_test() {
  let string_resolver = fn(s) { "resolved:" <> s }
  let list_resolver = fn(l) { "list:[" <> string.join(l, ",") <> "]" }

  [
    // Primitive dispatch
    #(
      #(
        accepted_types.PrimitiveType(primitive_types.String),
        dynamic.string("hello"),
      ),
      Ok("resolved:hello"),
    ),
    // Collection dispatch
    #(
      #(
        accepted_types.CollectionType(
          collection_types.List(
            accepted_types.PrimitiveType(primitive_types.NumericType(
              numeric_types.Integer,
            )),
          ),
        ),
        dynamic.list([dynamic.int(1), dynamic.int(2)]),
      ),
      Ok("list:[1,2]"),
    ),
    // Modifier dispatch - Optional with value
    #(
      #(
        accepted_types.ModifierType(
          modifier_types.Optional(accepted_types.PrimitiveType(
            primitive_types.String,
          )),
        ),
        dynamic.string("present"),
      ),
      Ok("resolved:present"),
    ),
    // Modifier dispatch - Defaulted with None uses default
    #(
      #(
        accepted_types.ModifierType(modifier_types.Defaulted(
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Integer,
          )),
          "99",
        )),
        dynamic.nil(),
      ),
      Ok("resolved:99"),
    ),
    // Refinement dispatch - OneOf(Defaulted(String)) with value provided
    #(
      #(
        accepted_types.RefinementType(refinement_types.OneOf(
          accepted_types.ModifierType(modifier_types.Defaulted(
            accepted_types.PrimitiveType(primitive_types.String),
            "production",
          )),
          set.from_list(["production", "staging"]),
        )),
        dynamic.string("staging"),
      ),
      Ok("resolved:staging"),
    ),
    // Refinement dispatch - OneOf(Defaulted(String)) with None uses default
    #(
      #(
        accepted_types.RefinementType(refinement_types.OneOf(
          accepted_types.ModifierType(modifier_types.Defaulted(
            accepted_types.PrimitiveType(primitive_types.String),
            "production",
          )),
          set.from_list(["production", "staging"]),
        )),
        dynamic.nil(),
      ),
      Ok("resolved:production"),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    accepted_types.resolve_to_string(typ, value, string_resolver, list_resolver)
    |> result_to_ok_string_from_string_error
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
