import caffeine_lang/types/resolved/resolved_sli

/// An SLO intance with all the aggregated information from previous steps.
///
/// Example:
/// ```
/// Slo(
///   window_in_days: 30,
///   threshold: 99.5,
///   service_name: "super_scalabale_web_service",
///   team_name: "badass_platform_team",
///   sli: ...
/// )
/// ```
pub type Slo {
  Slo(
    window_in_days: Int,
    threshold: Float,
    service_name: String,
    team_name: String,
    sli: resolved_sli.Sli,
  )
}
