// ==== Unresolved Specification Parsing Types ====
/// Unresolved version of Service used during parsing
pub type ServiceUnresolved {
  ServiceUnresolved(name: String, sli_types: List(String))
}

/// Unresolved version of SliType used during parsing
pub type SliTypeUnresolved {
  SliTypeUnresolved(name: String, query_template_type: String)
}

/// Unresolved version of QueryTemplateType used during parsing
pub type QueryTemplateTypeUnresolved {
  GoodOverBadQueryTemplateUnresolved(
    numerator_query: String,
    denominator_query: String,
    filters: List(String),
  )
}
