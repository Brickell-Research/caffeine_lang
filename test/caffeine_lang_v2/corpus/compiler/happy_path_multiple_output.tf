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

resource "datadog_service_level_objective" "acme_payments_slos_checkout_availability" {
  name = "checkout_availability"
  tags = ["managed_by:caffeine"]
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

resource "datadog_service_level_objective" "acme_payments_slos_checkout_latency_p99" {
  name = "checkout_latency_p99"
  tags = ["managed_by:caffeine"]
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

resource "datadog_service_level_objective" "acme_platform_slos_auth_service_availability" {
  name = "auth_service_availability"
  tags = ["managed_by:caffeine"]
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
