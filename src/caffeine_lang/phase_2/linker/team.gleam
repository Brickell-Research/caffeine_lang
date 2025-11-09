import caffeine_lang/phase_2/linker/slo

/// A team is a named entity that owns a set of SLOs.
pub type Team {
  Team(name: String, slos: List(slo.Slo))
}
