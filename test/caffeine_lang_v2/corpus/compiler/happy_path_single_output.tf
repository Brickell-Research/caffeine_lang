resource "datadog_service_level_objective" "acme_payments_slos_checkout_availability" {
  name = "acme_payments_slos_checkout_availability"
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
