// ==== Pre Sugared Specification Parsing Types ====
pub type ServiceUnresolved {
  ServiceUnresolved(name: String, sli_types: List(String))
}

pub type SliTypeUnresolved {
  SliTypeUnresolved(name: String, query_template: String, filters: List(String))
}
