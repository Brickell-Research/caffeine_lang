import caffeine_query_language/parser.{type ExpContainer}

/// QueryTemplateType used during parsing
pub type QueryTemplateType {
  QueryTemplateType(
    name: String,
    specification_of_query_templates: List(String),
    query: ExpContainer,
  )
}
