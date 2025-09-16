import caffeine_lang/types/accepted_types.{type AcceptedTypes}
import caffeine_lang/types/generic_dictionary.{type GenericDictionary}

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
  Slo(
    filters: GenericDictionary,
    threshold: Float,
    sli_type: String,
    service_name: String,
    window_in_days: Int,
  )
}

// ================================================

// ==== Specification Types ====
/// A service is a named entity that supports a set of SLO types.
pub type Service {
  Service(name: String, supported_sli_types: List(SliType))
}

/// A SliType is a named entity that represents the generic (as possible) definition of an SLI
/// that references a query template.
pub type SliType {
  SliType(
    name: String,
    query_template_type: QueryTemplateType,
    metric_attributes: GenericDictionary,
    filters: List(QueryTemplateFilter),
  )
}

pub type QueryTemplateType {
  QueryTemplateType(metric_attributes: List(QueryTemplateFilter), name: String)
}

/// A QueryTemplateFilter is a single definition of a filter that can be applied to a query template
/// to narrow down its scope.
pub type QueryTemplateFilter {
  QueryTemplateFilter(attribute_name: String, attribute_type: AcceptedTypes)
}
// ================================================
