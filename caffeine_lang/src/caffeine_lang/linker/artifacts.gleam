/// Dependency relationship types used across the compiler pipeline.
/// Types of dependency relationships between expectations.
pub type DependencyRelationType {
  /// If dependency down, dependent down.
  Hard
  /// Dependent can continue operating, either unscathed or within a degraded state if dependency down.
  Soft
}

/// Parses a string into a DependencyRelationType, returning Error(Nil) for unknown types.
@internal
pub fn parse_relation_type(s: String) -> Result(DependencyRelationType, Nil) {
  case s {
    "hard" -> Ok(Hard)
    "soft" -> Ok(Soft)
    _ -> Error(Nil)
  }
}

/// Converts a DependencyRelationType to its string representation.
@internal
pub fn relation_type_to_string(rt: DependencyRelationType) -> String {
  case rt {
    Hard -> "hard"
    Soft -> "soft"
  }
}
