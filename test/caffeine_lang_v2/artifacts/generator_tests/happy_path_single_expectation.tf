terraform {
  required_providers {
    datadog = { source = "DataDog/datadog" }
  }
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
}

resource "datadog_service_level_objective" "expectation_1" {
  description = "SLO managed by Caffeine"
  name = "expectation_1"
  tags = ["managed-by:caffeine", "blueprint:blueprint_1"]
  type = "metric"

  query {
    denominator = "sum:requests.success{*}.as_count()"
    numerator = "sum:requests.success{*}.as_count()"
  }
  thresholds {
    target = 99.9
    timeframe = "30d"
  }
}