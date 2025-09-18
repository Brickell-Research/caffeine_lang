import gleam/dict

// ==== Unresolved Specification Parsing Types ====
/// Unresolved version of Service used during parsing
pub type ServiceUnresolved {
  ServiceUnresolved(name: String, sli_types: List(String))
}

/// Unresolved version of SliType used during parsing
pub type SliTypeUnresolved {
  SliTypeUnresolved(
    name: String,
    query_template_type: String,
    metric_attributes: dict.Dict(String, String),
    filters: List(String),
  )
}

/// Unresolved version of QueryTemplateType used during parsing
pub type QueryTemplateTypeUnresolved {
  QueryTemplateTypeUnresolved(name: String, metric_attributes: List(String))
}
