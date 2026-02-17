import caffeine_lang/analysis/vendor
import caffeine_lang/constants
import test_helpers

// ==== Vendor Resolution ====
// * ✅ known vendors resolve to Ok
// * ✅ unknown vendor returns Error
pub fn resolve_vendor_test() {
  [
    #(
      "known vendors resolve to Ok - datadog",
      constants.vendor_datadog,
      Ok(vendor.Datadog),
    ),
    #(
      "known vendors resolve to Ok - honeycomb",
      constants.vendor_honeycomb,
      Ok(vendor.Honeycomb),
    ),
    #(
      "known vendors resolve to Ok - dynatrace",
      constants.vendor_dynatrace,
      Ok(vendor.Dynatrace),
    ),
    #(
      "known vendors resolve to Ok - newrelic",
      constants.vendor_newrelic,
      Ok(vendor.NewRelic),
    ),
    #("unknown vendor returns Error", "unknown_vendor", Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(vendor.resolve_vendor)
}
