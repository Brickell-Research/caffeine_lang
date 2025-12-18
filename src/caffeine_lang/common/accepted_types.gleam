/// AcceptedTypes is a union of all the types that can be used as filters. It is recursive
/// to allow for nested filters. This may be a bug in the future since it seems it may
/// infinitely recurse.
pub type AcceptedTypes {
  PrimitiveType(PrimitiveTypes)
  CollectionType(CollectionTypes)
  ModifierType(ModifierTypes)
}

pub type PrimitiveTypes {
  Boolean
  Float
  Integer
  String
}

pub type CollectionTypes {
  Dict(AcceptedTypes, AcceptedTypes)
  List(AcceptedTypes)
}

// Modifier types are a special class of types that alter the value semantics of
/// the attribute they are bound to.
pub type ModifierTypes {
  Optional(AcceptedTypes)
  /// Defaulted type stores the inner type and its default value as a string
  /// e.g., Defaulted(Integer, "10") means an optional integer with default 10
  Defaulted(AcceptedTypes, String)
}

/// Converts an AcceptedTypes to its string representation.
pub fn accepted_type_to_string(accepted_type: AcceptedTypes) -> String {
  case accepted_type {
    PrimitiveType(primitive) ->
      case primitive {
        Boolean -> "Boolean"
        Float -> "Float"
        Integer -> "Integer"
        String -> "String"
      }
    CollectionType(collection) ->
      case collection {
        Dict(key_type, value_type) ->
          "Dict("
          <> accepted_type_to_string(key_type)
          <> ", "
          <> accepted_type_to_string(value_type)
          <> ")"
        List(inner_type) ->
          "List(" <> accepted_type_to_string(inner_type) <> ")"
      }
    ModifierType(modifier) ->
      case modifier {
        Optional(inner_type) ->
          "Optional(" <> accepted_type_to_string(inner_type) <> ")"
        Defaulted(inner_type, default_val) ->
          "Defaulted("
          <> accepted_type_to_string(inner_type)
          <> ", "
          <> default_val
          <> ")"
      }
  }
}
