// ==== Pre Sugared Specification Parsing Types ====
pub type ServicePreSugared {
  ServicePreSugared(name: String, sli_types: List(String))
}

pub type SliTypePreSugared {
  SliTypePreSugared(name: String, query_template: String, filters: List(String))
}
