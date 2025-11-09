import caffeine_lang/phase_1/parser/unresolved_slo

/// Team used during parsing
pub type Team {
  Team(name: String, slos: List(unresolved_slo.Slo))
}
