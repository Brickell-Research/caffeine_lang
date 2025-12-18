import caffeine_lang/common/accepted_types
import test_helpers

// ==== Accepted Type To String Tests ====
// ==== Primitives ====
// * ✅ Boolean
// * ✅ Float
// * ✅ Integer
// * ✅ String
// ==== Collections - Dict ====
// * ✅ Dict(String, String)
// * ✅ Dict(String, Integer)
// * ✅ Dict(String, Float)
// * ✅ Dict(String, Boolean)
// ==== Collections - List ====
// * ✅ List(String)
// * ✅ List(Integer)
// * ✅ List(Float)
// * ✅ List(Boolean)
// ==== Modifier Types - Optional ====
// * ✅ Optional(String)
// * ✅ Optional(Integer)
// * ✅ Optional(Float)
// * ✅ Optional(Boolean)
// * ✅ Optional(List(String))
// * ✅ Optional(Dict(String, String))
// ==== Modifier Types - Defaulted (only primitives allowed) ====
// * ✅ Defaulted(String, default)
// * ✅ Defaulted(Integer, 10)
pub fn accepted_type_to_string_test() {
  [
    // ==== Primitives ====
    #(accepted_types.PrimitiveType(accepted_types.Boolean), "Boolean"),
    #(accepted_types.PrimitiveType(accepted_types.Float), "Float"),
    #(accepted_types.PrimitiveType(accepted_types.Integer), "Integer"),
    #(accepted_types.PrimitiveType(accepted_types.String), "String"),
    // ==== Collections - Dict ====
    #(
      accepted_types.CollectionType(accepted_types.Dict(
        accepted_types.PrimitiveType(accepted_types.String),
        accepted_types.PrimitiveType(accepted_types.String),
      )),
      "Dict(String, String)",
    ),
    #(
      accepted_types.CollectionType(accepted_types.Dict(
        accepted_types.PrimitiveType(accepted_types.String),
        accepted_types.PrimitiveType(accepted_types.Integer),
      )),
      "Dict(String, Integer)",
    ),
    #(
      accepted_types.CollectionType(accepted_types.Dict(
        accepted_types.PrimitiveType(accepted_types.String),
        accepted_types.PrimitiveType(accepted_types.Float),
      )),
      "Dict(String, Float)",
    ),
    #(
      accepted_types.CollectionType(accepted_types.Dict(
        accepted_types.PrimitiveType(accepted_types.String),
        accepted_types.PrimitiveType(accepted_types.Boolean),
      )),
      "Dict(String, Boolean)",
    ),
    // ==== Collections - List ====
    #(
      accepted_types.CollectionType(
        accepted_types.List(accepted_types.PrimitiveType(accepted_types.String)),
      ),
      "List(String)",
    ),
    #(
      accepted_types.CollectionType(
        accepted_types.List(accepted_types.PrimitiveType(accepted_types.Integer)),
      ),
      "List(Integer)",
    ),
    #(
      accepted_types.CollectionType(
        accepted_types.List(accepted_types.PrimitiveType(accepted_types.Float)),
      ),
      "List(Float)",
    ),
    #(
      accepted_types.CollectionType(
        accepted_types.List(accepted_types.PrimitiveType(accepted_types.Boolean)),
      ),
      "List(Boolean)",
    ),
    // ==== Modifier Types - Optional basic types ====
    #(
      accepted_types.ModifierType(
        accepted_types.Optional(
          accepted_types.PrimitiveType(accepted_types.String),
        ),
      ),
      "Optional(String)",
    ),
    #(
      accepted_types.ModifierType(
        accepted_types.Optional(
          accepted_types.PrimitiveType(accepted_types.Integer),
        ),
      ),
      "Optional(Integer)",
    ),
    #(
      accepted_types.ModifierType(
        accepted_types.Optional(
          accepted_types.PrimitiveType(accepted_types.Float),
        ),
      ),
      "Optional(Float)",
    ),
    #(
      accepted_types.ModifierType(
        accepted_types.Optional(
          accepted_types.PrimitiveType(accepted_types.Boolean),
        ),
      ),
      "Optional(Boolean)",
    ),
    // ==== Modifier Types - Optional nested types ====
    #(
      accepted_types.ModifierType(
        accepted_types.Optional(
          accepted_types.CollectionType(
            accepted_types.List(
              accepted_types.PrimitiveType(accepted_types.String),
            ),
          ),
        ),
      ),
      "Optional(List(String))",
    ),
    #(
      accepted_types.ModifierType(
        accepted_types.Optional(
          accepted_types.CollectionType(accepted_types.Dict(
            accepted_types.PrimitiveType(accepted_types.String),
            accepted_types.PrimitiveType(accepted_types.String),
          )),
        ),
      ),
      "Optional(Dict(String, String))",
    ),
    // ==== Modifier Types - Defaulted basic types ====
    #(
      accepted_types.ModifierType(
        accepted_types.Defaulted(
          accepted_types.PrimitiveType(accepted_types.String),
          "default",
        ),
      ),
      "Defaulted(String, default)",
    ),
    #(
      accepted_types.ModifierType(
        accepted_types.Defaulted(
          accepted_types.PrimitiveType(accepted_types.Integer),
          "10",
        ),
      ),
      "Defaulted(Integer, 10)",
    ),
  ]
  |> test_helpers.array_based_test_executor_1(
    accepted_types.accepted_type_to_string,
  )
}
