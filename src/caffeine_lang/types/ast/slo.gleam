import caffeine_lang/types/ast/typed_instantiation_of_query_templates

/// An SLO is an expectation set by stakeholders upon a metric emulating the user experience as best as possible.
pub type Slo {
  Slo(
    typed_instatiation_of_query_templatized_variables: typed_instantiation_of_query_templates.TypedInstantiationOfQueryTemplates,
    threshold: Float,
    sli_type: String,
    service_name: String,
    window_in_days: Int,
  )
}
