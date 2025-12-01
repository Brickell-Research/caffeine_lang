terraform {
  required_providers {
    datadog = { source = "DataDog/datadog" }
  }
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
}

resource "datadog_service_level_objective" "api_availability" {
  description = "SLO managed by Caffeine"
  name = "api_availability"
  tags = ["managed-by:caffeine", "blueprint:availability_blueprint"]
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

resource "datadog_service_level_objective" "api_latency" {
  description = "SLO managed by Caffeine"
  name = "api_latency"
  tags = ["managed-by:caffeine", "blueprint:latency_blueprint"]
  type = "metric"

  query {
    denominator = "avg:requests.latency{*}.as_count()"
    numerator = "avg:requests.latency{*}.as_count()"
  }
  thresholds {
    target = 95.0
    timeframe = "7d"
  }
}

resource "datadog_service_level_objective" "checkout_availability" {
  description = "SLO managed by Caffeine"
  name = "checkout_availability"
  tags = ["managed-by:caffeine", "blueprint:availability_blueprint"]
  type = "metric"

  query {
    denominator = "sum:requests.success{*}.as_count()"
    numerator = "sum:requests.success{*}.as_count()"
  }
  thresholds {
    target = 99.5
    timeframe = "30d"
  }
}