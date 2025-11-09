import caffeine_lang/phase_2/linker/specification_of_query_templates
import caffeine_query_language/parser.{type ExpContainer}

pub type QueryTemplateType {
  QueryTemplateType(
    specification_of_query_templates: specification_of_query_templates.SpecificationOfQueryTemplates,
    name: String,
    query: ExpContainer,
  )
}
