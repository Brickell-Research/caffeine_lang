/// AcceptedTypes is a union of all the types that can be used as filters. It is recursive
/// to allow for nested filters. This may be a bug in the future since it seems it may
/// infinitely recurse.
pub type AcceptedTypes {
  Boolean
  Float
  Integer
  String
  Dict(AcceptedTypes, AcceptedTypes)
  List(AcceptedTypes)
  Modifier(ModifierTypes)
}

/// Modifier types are a special class of types.
pub type ModifierTypes {
  Optional(AcceptedTypes)
  /// Defaulted type stores the inner type and its default value as a string
  /// e.g., Defaulted(Integer, "10") means an optional integer with default 10
  Defaulted(AcceptedTypes, String)
}

/// Converts an AcceptedTypes to its string representation.
pub fn accepted_type_to_string(accepted_type: AcceptedTypes) -> String {
  case accepted_type {
    Boolean -> "Boolean"
    Float -> "Float"
    Integer -> "Integer"
    String -> "String"
    Dict(key_type, value_type) ->
      "Dict("
      <> accepted_type_to_string(key_type)
      <> ", "
      <> accepted_type_to_string(value_type)
      <> ")"
    List(inner_type) -> "List(" <> accepted_type_to_string(inner_type) <> ")"
    Modifier(modifier_type) ->
      case modifier_type {
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
