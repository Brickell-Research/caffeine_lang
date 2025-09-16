import gleam/dict

pub type UnresolvedTeam {
  UnresolvedTeam(name: String, slos: List(UnresolvedSlo))
}

pub type UnresolvedSlo {
  UnresolvedSlo(
    filters: dict.Dict(String, String),
    threshold: Float,
    sli_type: String,
    service_name: String,
    window_in_days: Int,
  )
}
