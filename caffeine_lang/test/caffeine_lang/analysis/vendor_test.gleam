import caffeine_lang/analysis/vendor
import caffeine_lang/constants
import test_helpers

// ==== Vendor Resolution ====
// * ✅ known vendors resolve to Ok
// * ✅ unknown vendor returns Error
pub fn resolve_vendor_test() {
  [
    #(constants.vendor_datadog, Ok(vendor.Datadog)),
    #(constants.vendor_honeycomb, Ok(vendor.Honeycomb)),
    #(constants.vendor_dynatrace, Ok(vendor.Dynatrace)),
    #(constants.vendor_newrelic, Ok(vendor.NewRelic)),
    #("unknown_vendor", Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(vendor.resolve_vendor)
}
