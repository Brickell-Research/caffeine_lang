import caffeine_lang/types/ast/query_template_type
import gleam/dict

pub type ResolvedSlo {
  ResolvedSlo(
    window_in_days: Int,
    threshold: Float,
    service_name: String,
    team_name: String,
    sli: ResolvedSli,
  )
}

pub type ResolvedSli {
  ResolvedSli(
    query_template_type: query_template_type.QueryTemplateType,
    metric_attributes: dict.Dict(String, String),
  )
}
