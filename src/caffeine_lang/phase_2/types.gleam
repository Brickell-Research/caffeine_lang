import caffeine_lang/common_types/accepted_types.{type AcceptedTypes}
import caffeine_lang/common_types/generic_dictionary.{type GenericDictionary}

// ==== Useful Type Aliases ====
/// A TypedInstantiationOfQueryTemplates is a dictionary of query template names to their typed instantiations.
pub type TypedInstantiationOfQueryTemplates =
  GenericDictionary

/// A TypedInstantiationOfMetrics is a dictionary of metric names to their typed instantiations.
pub type TypedInstantiationOfMetrics =
  GenericDictionary

/// A SpecificationOfQueryTemplates is a list of expected basic types by name and type.
pub type SpecificationOfQueryTemplates =
  List(BasicType)

/// A SpecificationOfMetrics is a list of expected metric filters by name and type.
pub type SpecificationOfMetrics =
  List(BasicType)

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
    typed_instatiation_of_query_templatized_variables: TypedInstantiationOfQueryTemplates,
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
    typed_instatiation_of_query_templates: TypedInstantiationOfQueryTemplates,
    specification_of_query_templatized_variables: SpecificationOfQueryTemplates,
  )
}

pub type QueryTemplateType {
  QueryTemplateType(
    specification_of_query_templates: SpecificationOfQueryTemplates,
    name: String,
  )
}

/// A BasicType represents a fundamental data type with a name and type.
pub type BasicType {
  BasicType(attribute_name: String, attribute_type: AcceptedTypes)
}
// ================================================
