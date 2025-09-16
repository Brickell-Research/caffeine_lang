import gleam/dict

pub type UnresolvedTeam {
  UnresolvedTeam(name: String, slos: List(UnresolvedSlo))
}

pub type UnresolvedSlo {
  UnresolvedSlo(
    typed_instatiation_of_query_templatized_variables: dict.Dict(String, String),
    threshold: Float,
    sli_type: String,
    service_name: String,
    window_in_days: Int,
  )
}
