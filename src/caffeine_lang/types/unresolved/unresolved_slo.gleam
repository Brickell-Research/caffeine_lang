import gleam/dict

/// SLO used during parsing
pub type Slo {
  Slo(
    typed_instatiation_of_query_templatized_variables: dict.Dict(String, String),
    threshold: Float,
    sli_type: String,
    service_name: String,
    window_in_days: Int,
  )
}
