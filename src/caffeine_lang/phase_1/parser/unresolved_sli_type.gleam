import gleam/dict

/// SliType used during parsing
pub type SliType {
  SliType(
    name: String,
    query_template_type: String,
    typed_instatiation_of_query_templates: dict.Dict(String, String),
    specification_of_query_templatized_variables: List(String),
  )
}
