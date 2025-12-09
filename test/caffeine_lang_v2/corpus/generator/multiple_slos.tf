resource "datadog_service_level_objective" "org_team_auth_latency_slo" {
  name = "org/team/auth/latency_slo"
  type = "metric"

  query {
    denominator = "sum:http.requests{*}"
    numerator = "sum:http.requests{status:2xx}"
  }
  thresholds {
    target = 99.9
    timeframe = "30d"
  }
}

resource "datadog_service_level_objective" "org_team_api_availability_slo" {
  name = "org/team/api/availability_slo"
  type = "metric"

  query {
    denominator = "sum:api.requests{*}"
    numerator = "sum:api.requests{!status:5xx}"
  }
  thresholds {
    target = 99.5
    timeframe = "7d"
  }
}
