import caffeine_lang/types/ast/specification_of_query_templates

pub type QueryTemplateType {
  QueryTemplateType(
    specification_of_query_templates: specification_of_query_templates.SpecificationOfQueryTemplates,
    name: String,
  )
}
