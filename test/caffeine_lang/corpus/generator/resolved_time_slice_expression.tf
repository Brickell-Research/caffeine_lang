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

resource "datadog_service_level_objective" "org_team_auth_time_slice_slo" {
  name = "Time Slice SLO"
  tags = ["managed_by:caffeine", "caffeine_version:0.2.9", "org:org", "team:test_team", "service:team", "blueprint:test_blueprint", "expectation:Time Slice SLO", "artifact:SLO"]
  type = "time_slice"

  sli_specification {
    time_slice {
      comparator = ">"
      query_interval_seconds = 300
      threshold = 99.5

      query {
        formula {
          formula_expression = "query1"
        }
        query {
          metric_query {
            data_source = "metrics"
            name = "query1"
            query = "avg:system.cpu.user{env:production}"
          }
        }
      }
    }
  }
  thresholds {
    target = 99.9
    timeframe = "30d"
  }
}
