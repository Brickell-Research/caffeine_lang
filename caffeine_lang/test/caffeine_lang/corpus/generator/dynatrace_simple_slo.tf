terraform {
  required_providers {
    dynatrace = {
      source = "dynatrace-oss/dynatrace"
      version = "~> 1.0"
    }
  }
}

provider "dynatrace" {
  dt_api_token = var.dynatrace_api_token
  dt_env_url = var.dynatrace_env_url
}

variable "dynatrace_env_url" {
  description = "Dynatrace environment URL"
  type = string
}

variable "dynatrace_api_token" {
  description = "Dynatrace API token"
  sensitive = true
  type = string
}

resource "dynatrace_slo_v2" "acme_payments_api_success_rate" {
  custom_description = "Managed by Caffeine (acme/platform/payments)"
  enabled = true
  evaluation_type = "AGGREGATE"
  evaluation_window = "-30d"
  metric_expression = "builtin:service.errors.server.successCount:splitBy() / builtin:service.requestCount.server:splitBy()"
  metric_name = "acme_payments_api_success_rate"
  name = "API Success Rate"
  target_success = 99.5
}
