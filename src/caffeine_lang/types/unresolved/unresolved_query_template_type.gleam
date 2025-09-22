import caffeine_lang/cql/parser.{type ExpContainer}

/// QueryTemplateType used during parsing
pub type QueryTemplateType {
  QueryTemplateType(
    name: String,
    specification_of_query_templates: List(String),
    query: ExpContainer,
  )
}
