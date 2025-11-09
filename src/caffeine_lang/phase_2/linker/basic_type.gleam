import caffeine_lang/types/accepted_types

/// A BasicType represents a fundamental data type with a name and type.
pub type BasicType {
  BasicType(
    attribute_name: String,
    attribute_type: accepted_types.AcceptedTypes,
  )
}
