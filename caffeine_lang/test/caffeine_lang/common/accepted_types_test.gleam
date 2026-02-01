import caffeine_lang/common/accepted_types
import caffeine_lang/common/collection_types
import caffeine_lang/common/modifier_types
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/common/refinement_types
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/set
import gleam/string
import gleeunit/should
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
// * ✅ Invalid: Defaulted only allows primitives or refinements
// * ✅ Defaulted with refinement inner type (resolved type alias)
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
    // Invalid - Defaulted only allows primitives, refinements, or collections
    #("Defaulted(List(String), default)", Error(Nil)),
    // Defaulted with refinement inner type (what happens after type alias resolution)
    #(
      "Defaulted(String { x | x in { demo, development, production } }, production)",
      Ok(
        accepted_types.ModifierType(modifier_types.Defaulted(
          accepted_types.RefinementType(refinement_types.OneOf(
            accepted_types.PrimitiveType(primitive_types.String),
            set.from_list(["demo", "development", "production"]),
          )),
          "production",
        )),
      ),
    ),
    // Invalid - Defaulted with refinement but default not in set
    #(
      "Defaulted(String { x | x in { demo, production } }, invalid)",
      Error(Nil),
    ),
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

// ==== decode_list_values_to_strings ====
// * ✅ decodes list of strings
// * ✅ decodes list of integers to strings
// * ✅ fails on non-list input
pub fn decode_list_values_to_strings_test() {
  // List of strings
  decode.run(
    dynamic.list([dynamic.string("a"), dynamic.string("b")]),
    accepted_types.decode_list_values_to_strings(accepted_types.PrimitiveType(
      primitive_types.String,
    )),
  )
  |> should.equal(Ok(["a", "b"]))

  // List of integers decoded to strings
  decode.run(
    dynamic.list([dynamic.int(1), dynamic.int(2)]),
    accepted_types.decode_list_values_to_strings(
      accepted_types.PrimitiveType(primitive_types.NumericType(
        numeric_types.Integer,
      )),
    ),
  )
  |> should.equal(Ok(["1", "2"]))

  // Non-list input fails
  decode.run(
    dynamic.string("not a list"),
    accepted_types.decode_list_values_to_strings(accepted_types.PrimitiveType(
      primitive_types.String,
    )),
  )
  |> should.be_error()
}

// ==== get_numeric_type ====
// * ✅ Integer primitive -> Integer
// * ✅ Float primitive -> Float
// * ✅ Non-numeric types fall back to Integer
pub fn get_numeric_type_test() {
  [
    #(
      accepted_types.PrimitiveType(primitive_types.NumericType(
        numeric_types.Integer,
      )),
      numeric_types.Integer,
    ),
    #(
      accepted_types.PrimitiveType(primitive_types.NumericType(
        numeric_types.Float,
      )),
      numeric_types.Float,
    ),
    // Fallback cases
    #(
      accepted_types.PrimitiveType(primitive_types.String),
      numeric_types.Integer,
    ),
    #(
      accepted_types.PrimitiveType(primitive_types.Boolean),
      numeric_types.Integer,
    ),
    #(accepted_types.TypeAliasRef("_env"), numeric_types.Integer),
    #(
      accepted_types.CollectionType(
        collection_types.List(accepted_types.PrimitiveType(
          primitive_types.String,
        )),
      ),
      numeric_types.Integer,
    ),
  ]
  |> test_helpers.array_based_test_executor_1(accepted_types.get_numeric_type)
}

// ==== is_optional_or_defaulted ====
// * ✅ Optional -> True
// * ✅ Defaulted -> True
// * ✅ OneOf wrapping Optional -> True
// * ✅ Plain primitive -> False
// * ✅ Collection -> False
pub fn is_optional_or_defaulted_test() {
  [
    #(
      accepted_types.ModifierType(
        modifier_types.Optional(accepted_types.PrimitiveType(
          primitive_types.String,
        )),
      ),
      True,
    ),
    #(
      accepted_types.ModifierType(modifier_types.Defaulted(
        accepted_types.PrimitiveType(primitive_types.String),
        "hello",
      )),
      True,
    ),
    #(
      accepted_types.RefinementType(refinement_types.OneOf(
        accepted_types.ModifierType(
          modifier_types.Optional(accepted_types.PrimitiveType(
            primitive_types.String,
          )),
        ),
        set.from_list(["a", "b"]),
      )),
      True,
    ),
    #(accepted_types.PrimitiveType(primitive_types.String), False),
    #(
      accepted_types.CollectionType(
        collection_types.List(accepted_types.PrimitiveType(
          primitive_types.String,
        )),
      ),
      False,
    ),
    #(accepted_types.TypeAliasRef("_env"), False),
  ]
  |> test_helpers.array_based_test_executor_1(
    accepted_types.is_optional_or_defaulted,
  )
}

// ==== all_type_metas ====
// * ✅ returns non-empty list with entries from all 4 categories
pub fn all_type_metas_test() {
  let metas = accepted_types.all_type_metas()
  // Should have entries from primitives, collections, modifiers, and refinements
  { metas != [] } |> should.be_true()

  // Verify it includes entries from each category by checking known names
  let names = list.map(metas, fn(m) { m.name })
  list.contains(names, "Boolean") |> should.be_true()
  list.contains(names, "List") |> should.be_true()
  list.contains(names, "Optional") |> should.be_true()
  list.contains(names, "OneOf") |> should.be_true()
}

// ==== try_each_inner ====
// * ✅ PrimitiveType -> calls f with self
// * ✅ TypeAliasRef -> calls f with self
// * ✅ CollectionType -> delegates to collection_types.try_each_inner
// * ✅ ModifierType -> delegates to modifier_types.try_each_inner
// * ✅ RefinementType -> delegates to refinement_types.try_each_inner
// * ✅ Error propagation
pub fn try_each_inner_test() {
  let always_ok = fn(_) { Ok(Nil) }

  // PrimitiveType calls f with self
  accepted_types.try_each_inner(
    accepted_types.PrimitiveType(primitive_types.String),
    always_ok,
  )
  |> should.equal(Ok(Nil))

  // TypeAliasRef calls f with self
  accepted_types.try_each_inner(accepted_types.TypeAliasRef("_env"), always_ok)
  |> should.equal(Ok(Nil))

  // CollectionType - List calls f once
  accepted_types.try_each_inner(
    accepted_types.CollectionType(
      collection_types.List(accepted_types.PrimitiveType(primitive_types.String)),
    ),
    always_ok,
  )
  |> should.equal(Ok(Nil))

  // ModifierType - Optional calls f with inner
  accepted_types.try_each_inner(
    accepted_types.ModifierType(
      modifier_types.Optional(accepted_types.PrimitiveType(
        primitive_types.String,
      )),
    ),
    always_ok,
  )
  |> should.equal(Ok(Nil))

  // RefinementType - OneOf calls f with inner
  accepted_types.try_each_inner(
    accepted_types.RefinementType(refinement_types.OneOf(
      accepted_types.PrimitiveType(primitive_types.String),
      set.from_list(["a"]),
    )),
    always_ok,
  )
  |> should.equal(Ok(Nil))

  // Error propagation - f returns error
  let always_err = fn(_) { Error("fail") }
  accepted_types.try_each_inner(
    accepted_types.PrimitiveType(primitive_types.String),
    always_err,
  )
  |> should.equal(Error("fail"))
}

// ==== map_inner ====
// * ✅ PrimitiveType -> calls f with self
// * ✅ TypeAliasRef -> calls f with self
// * ✅ CollectionType -> transforms inner types
// * ✅ ModifierType -> transforms inner type
// * ✅ RefinementType -> transforms inner type
pub fn map_inner_test() {
  let identity = fn(t) { t }

  // PrimitiveType -> f is called on self
  accepted_types.map_inner(
    accepted_types.PrimitiveType(primitive_types.String),
    identity,
  )
  |> should.equal(accepted_types.PrimitiveType(primitive_types.String))

  // TypeAliasRef -> f is called on self
  accepted_types.map_inner(accepted_types.TypeAliasRef("_env"), identity)
  |> should.equal(accepted_types.TypeAliasRef("_env"))

  // CollectionType List -> inner is transformed
  let to_bool = fn(_) { accepted_types.PrimitiveType(primitive_types.Boolean) }
  accepted_types.map_inner(
    accepted_types.CollectionType(
      collection_types.List(accepted_types.PrimitiveType(primitive_types.String)),
    ),
    to_bool,
  )
  |> should.equal(
    accepted_types.CollectionType(
      collection_types.List(accepted_types.PrimitiveType(
        primitive_types.Boolean,
      )),
    ),
  )

  // ModifierType Optional -> inner is transformed
  accepted_types.map_inner(
    accepted_types.ModifierType(
      modifier_types.Optional(accepted_types.PrimitiveType(
        primitive_types.String,
      )),
    ),
    to_bool,
  )
  |> should.equal(
    accepted_types.ModifierType(
      modifier_types.Optional(accepted_types.PrimitiveType(
        primitive_types.Boolean,
      )),
    ),
  )

  // RefinementType OneOf -> inner is transformed, set preserved
  accepted_types.map_inner(
    accepted_types.RefinementType(refinement_types.OneOf(
      accepted_types.PrimitiveType(primitive_types.String),
      set.from_list(["a", "b"]),
    )),
    to_bool,
  )
  |> should.equal(
    accepted_types.RefinementType(refinement_types.OneOf(
      accepted_types.PrimitiveType(primitive_types.Boolean),
      set.from_list(["a", "b"]),
    )),
  )
}
