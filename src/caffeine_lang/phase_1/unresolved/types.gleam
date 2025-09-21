import gleam/dict

// ==== Unresolved Specification Parsing Types ====
// ==== Specification Types ====
/// Unresolved version of Service used during parsing
pub type ServiceUnresolved {
  ServiceUnresolved(name: String, sli_types: List(String))
}

/// Unresolved version of SliType used during parsing
pub type SliTypeUnresolved {
  SliTypeUnresolved(
    name: String,
    query_template_type: String,
    typed_instatiation_of_query_templates: dict.Dict(String, String),
    specification_of_query_templatized_variables: List(String),
  )
}

/// Unresolved version of QueryTemplateType used during parsing
pub type QueryTemplateTypeUnresolved {
  QueryTemplateTypeUnresolved(
    name: String,
    specification_of_query_templates: List(String),
  )
}

// ==== Instantiation Types ====
/// Unresolved version of Team used during parsing
pub type UnresolvedTeam {
  UnresolvedTeam(name: String, slos: List(UnresolvedSlo))
}

/// Unresolved version of SLO used during parsing
pub type UnresolvedSlo {
  UnresolvedSlo(
    typed_instatiation_of_query_templatized_variables: dict.Dict(String, String),
    threshold: Float,
    sli_type: String,
    service_name: String,
    window_in_days: Int,
  )
}
