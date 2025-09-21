import caffeine_lang/phase_2/types as ast
import gleam/dict

/// An SLO intance with all the aggregated information from previous steps.
///
/// Example:
/// ```
/// ResolvedSlo(
///   window_in_days: 30,
///   threshold: 99.5,
///   service_name: "super_scalabale_web_service",
///   team_name: "badass_platform_team",
///   sli: ...
/// )
/// ```
pub type ResolvedSlo {
  ResolvedSlo(
    window_in_days: Int,
    threshold: Float,
    service_name: String,
    team_name: String,
    sli: ResolvedSli,
  )
}

/// An SLI intance with all the aggregated information from previous steps.
///
/// Example:
/// ```
/// ResolvedSli(
///   query_template_type: "good_over_bad",
///   metric_attributes: {
///     numerator_query: "max:latency(<100ms, {service="super_scalabale_web_service",requests_valid=true})",
///     denominator_query: "max:latency(<100ms, {service="super_scalabale_web_service"})",
///   }
/// )
/// ```
pub type ResolvedSli {
  ResolvedSli(
    query_template_type: ast.QueryTemplateType,
    metric_attributes: dict.Dict(String, String),
  )
}
