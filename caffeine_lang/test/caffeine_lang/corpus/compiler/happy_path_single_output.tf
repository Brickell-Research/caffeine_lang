terraform {
  required_providers {
    datadog = {
      source = "DataDog/datadog"
      version = "~> 3.0"
    }
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

# Caffeine: acme.payments.slos.checkout_availability (measurement: api_availability)
resource "datadog_service_level_objective" "acme_slos_checkout_availability" {
  name = "checkout_availability"
  tags = [
    "managed_by:caffeine",
    "caffeine_version:{{VERSION}}",
    "org:acme",
    "team:payments",
    "service:slos",
    "measurement:api_availability",
    "expectation:checkout_availability",
    "artifact:SLO",
    "env:production",
    "status:true",
  ]
  type = "metric"

  query {
    denominator = "sum:http.requests{env:production}"
    numerator = "sum:http.requests{env:production AND !status:true}"
  }
  thresholds {
    target = 99.95
    timeframe = "30d"
  }
}
