/// Type-safe wrappers for string identifiers used in IR metadata.
/// These non-opaque newtypes prevent accidental mixing of org, team, service,
/// blueprint, and expectation names at construction boundaries while keeping
/// unwrapping lightweight via pattern matching.
/// Organization name identifier.
pub type OrgName {
  OrgName(value: String)
}

/// Team name identifier.
pub type TeamName {
  TeamName(value: String)
}

/// Service name identifier.
pub type ServiceName {
  ServiceName(value: String)
}

/// Blueprint name identifier.
pub type BlueprintName {
  BlueprintName(value: String)
}

/// Expectation label identifier.
pub type ExpectationLabel {
  ExpectationLabel(value: String)
}
