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

resource "datadog_service_level_objective" "acme_slos_checkout_availability" {
  name = "checkout_availability"
  tags = ["managed_by:caffeine", "caffeine_version:0.2.16", "org:acme", "team:payments", "service:slos", "blueprint:api_availability", "expectation:checkout_availability", "artifact:SLO"]
  type = "metric"

  query {
    denominator = "sum:http.requests{env:production,service:checkout-api}"
    numerator = "sum:http.requests{env:production,service:checkout-api,!status:5xx}"
  }
  thresholds {
    target = 99.95
    timeframe = "30d"
  }
}

resource "datadog_service_level_objective" "acme_slos_checkout_latency_p99" {
  name = "checkout_latency_p99"
  tags = ["managed_by:caffeine", "caffeine_version:0.2.16", "org:acme", "team:payments", "service:slos", "blueprint:api_latency_p99", "expectation:checkout_latency_p99", "artifact:SLO"]
  type = "metric"

  query {
    denominator = "sum:http.latency.p99{env:production,service:checkout-api}"
    numerator = "sum:http.latency.p99{env:production,service:checkout-api,le:500}"
  }
  thresholds {
    target = 99.0
    timeframe = "7d"
  }
}

resource "datadog_service_level_objective" "acme_slos_auth_service_availability" {
  name = "auth_service_availability"
  tags = ["managed_by:caffeine", "caffeine_version:0.2.16", "org:acme", "team:platform", "service:slos", "blueprint:api_availability", "expectation:auth_service_availability", "artifact:SLO"]
  type = "metric"

  query {
    denominator = "sum:http.requests{env:production,service:auth-service}"
    numerator = "sum:http.requests{env:production,service:auth-service,!status:5xx}"
  }
  thresholds {
    target = 99.99
    timeframe = "30d"
  }
}
