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
  tags = ["managed_by:caffeine", "caffeine_version:0.2.3", "org:acme", "service:payments_slos", "expectation:checkout_availability", "artifact:SLO"]
  type = "metric"

  query {
    denominator = "sum:http.requests{env:production}"
    numerator = "sum:http.requests{env:production AND !status:True}"
  }
  thresholds {
    target = 99.95
    timeframe = "30d"
  }
}
