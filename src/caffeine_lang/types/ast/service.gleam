import caffeine_lang/types/ast/sli_type

/// A service is a named entity that supports a set of SLO types.
pub type Service {
  Service(name: String, supported_sli_types: List(sli_type.SliType))
}
