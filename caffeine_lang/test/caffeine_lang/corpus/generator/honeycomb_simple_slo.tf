terraform {
  required_providers {
    honeycombio = {
      source = "honeycombio/honeycombio"
      version = "~> 0.31"
    }
  }
}

provider "honeycombio" {
  api_key = var.honeycomb_api_key
}

variable "honeycomb_api_key" {
  description = "Honeycomb API key"
  sensitive = true
  type = string
}

variable "honeycomb_dataset" {
  description = "Honeycomb dataset slug"
  type = string
}

resource "honeycombio_derived_column" "acme_payments_api_success_rate_sli" {
  alias = "acme_payments_api_success_rate_sli"
  dataset = var.honeycomb_dataset
  expression = "LT($\"status_code\", 500)"
}

resource "honeycombio_slo" "acme_payments_api_success_rate" {
  dataset = var.honeycomb_dataset
  description = "Managed by Caffeine (acme/platform/payments)"
  name = "API Success Rate"
  sli = honeycombio_derived_column.acme_payments_api_success_rate_sli.alias
  tags = {
    managedby = "caffeine"
    caffeineversion = "v450"
    org = "acme"
    team = "platform"
    service = "payments"
    blueprint = "trace-availability"
    expectation = "api-success-rate"
  }
  target_percentage = 99.5
  time_period = 14
}
