// ==== Pre Sugared Specification Parsing Types ====
pub type ServiceUnresolved {
  ServiceUnresolved(name: String, sli_types: List(String))
}

pub type SliTypeUnresolved {
  SliTypeUnresolved(
    name: String,
    query_template_type: String,
    filters: List(String),
  )
}
