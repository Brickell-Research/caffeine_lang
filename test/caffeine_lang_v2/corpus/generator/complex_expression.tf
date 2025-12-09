resource "datadog_service_level_objective" "org_team_auth_composite_slo" {
  name = "org/team/auth/composite_slo"
  type = "metric"

  query {
    denominator = "sum:http.requests{*}"
    numerator = "(sum:http.requests{status:2xx} + sum:http.requests{status:3xx})"
  }
  thresholds {
    target = 99.9
    timeframe = "30d"
  }
}
