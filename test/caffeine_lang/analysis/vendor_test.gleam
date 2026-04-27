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
    #("unknown vendor returns Error", "unknown_vendor", Error(Nil)),
  ]
  |> test_helpers.table_test_1(vendor.resolve_vendor)
}
