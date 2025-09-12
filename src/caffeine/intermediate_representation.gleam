import gleam/dict

/// An organization represents the union of instantiations and specifications.
pub type Organization {
  Organization(teams: List(Team), service_definitions: List(Service))
}

// ==== Instantiation Types ====
/// A team is a named entity that owns a set of SLOs.
pub type Team {
  Team(name: String, slos: List(Slo))
}

/// An SLO is an expectation set by stakeholders upon a metric emulating the user experience as best as possible.
pub type Slo {
  Slo(filters: dict.Dict(String, String), threshold: Float, sli_type: String)
}

// ================================================

// ==== Specification Types ====
/// A service is a named entity that supports a set of SLO types.
pub type Service {
  Service(name: String, supported_sli_types: List(SliType))
}

/// A SliType is a named entity that represents the generic (as possible) definition of an SLI
/// that combines the query template and the filters.
pub type SliType {
  SliType(filters: List(SliFilter), name: String, query_template: String)
}

/// A SliFilter is a single definition of a filter that can be applied to an SLI's query
/// to narrow down its scope.
pub type SliFilter {
  SliFilter(
    attribute_name: String,
    attribute_type: AcceptedTypes,
    required: Bool,
  )
}

/// AcceptedTypes is a union of all the types that can be used as filters. It is recursive
/// to allow for nested filters. This may be a bug in the future since it seems it may
/// infinitely recurse.
pub type AcceptedTypes {
  Boolean
  Decimal
  Integer
  String
  List(AcceptedTypes)
}
// ================================================
