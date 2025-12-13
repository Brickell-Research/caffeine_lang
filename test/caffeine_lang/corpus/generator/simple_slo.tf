terraform {
  required_providers {
    datadog = { source = "DataDog/datadog", version = "~> 3.0" }
  }
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
}

variable "datadog_api_key" {
  description = "Datadog API key"
  sensitive = true
  type = string
}

variable "datadog_app_key" {
  description = "Datadog Application key"
  sensitive = true
  type = string
}

resource "datadog_service_level_objective" "org_team_auth_latency_slo" {
  name = "Auth Latency SLO"
  tags = ["managed_by:caffeine", "caffeine_version:0.2.14", "org:org", "team:test_team", "service:team", "blueprint:test_blueprint", "expectation:Auth Latency SLO", "artifact:SLO"]
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
