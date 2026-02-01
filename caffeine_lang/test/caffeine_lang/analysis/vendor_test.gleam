import caffeine_lang/analysis/vendor
import caffeine_lang/constants
import test_helpers

// ==== Vendor Resolution ====
// Note: Invalid vendors are now caught at parse time via refinement types,
// so we only test the valid case here.
// * ✅ vendor resolves
pub fn resolve_vendor_test() {
  [#(constants.vendor_datadog, vendor.Datadog)]
  |> test_helpers.array_based_test_executor_1(vendor.resolve_vendor)
}
