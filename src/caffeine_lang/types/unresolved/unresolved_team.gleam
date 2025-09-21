import caffeine_lang/types/unresolved/unresolved_slo

/// Team used during parsing
pub type Team {
  Team(name: String, slos: List(unresolved_slo.Slo))
}
