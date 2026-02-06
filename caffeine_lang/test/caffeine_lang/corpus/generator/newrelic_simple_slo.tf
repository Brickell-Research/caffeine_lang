terraform {
  required_providers {
    newrelic = {
      source = "newrelic/newrelic"
      version = "~> 3.0"
    }
  }
}

provider "newrelic" {
  account_id = var.newrelic_account_id
  api_key = var.newrelic_api_key
  region = var.newrelic_region
}

variable "newrelic_account_id" {
  description = "New Relic account ID"
  type = number
}

variable "newrelic_api_key" {
  description = "New Relic API key"
  sensitive = true
  type = string
}

variable "newrelic_region" {
  default = "US"
  description = "New Relic region"
  type = string
}

variable "newrelic_entity_guid" {
  description = "New Relic entity GUID"
  type = string
}

resource "newrelic_service_level" "acme_payments_api_success_rate" {
  description = "Managed by Caffeine (acme/platform/payments)"
  guid = var.newrelic_entity_guid
  name = "API Success Rate"

  events {
    account_id = var.newrelic_account_id

    valid_events {
      from = "Transaction"
      where = "appName = 'payments'"
    }
    good_events {
      from = "Transaction"
      where = "appName = 'payments' AND duration < 0.1"
    }
  }
  objective {
    target = 99.5

    time_window {
      rolling {
        count = 7
        unit = "DAY"
      }
    }
  }
}
