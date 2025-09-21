import caffeine_lang/types/ast/query_template_type
import caffeine_lang/types/ast/typed_instantiation_of_query_templates
import caffeine_lang/types/ast/specification_of_query_templates

/// A SliType is a named entity that represents the generic (as possible) definition of an SLI
/// that references a query template.
pub type SliType {
  SliType(
    name: String,
    query_template_type: query_template_type.QueryTemplateType,
    typed_instatiation_of_query_templates: typed_instantiation_of_query_templates.TypedInstantiationOfQueryTemplates,
    specification_of_query_templatized_variables: specification_of_query_templates.SpecificationOfQueryTemplates,
  )
}
