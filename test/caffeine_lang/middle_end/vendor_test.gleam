import caffeine_lang/common/errors
import caffeine_lang/middle_end/vendor
import test_helpers

// ==== Vendor Resolution ====
// ✅ vendor resolves
// ✅ vendor does not resolve
pub fn resolve_vendor_test() {
  [
    #("datadog", Ok(vendor.Datadog)),
    #(
      "unknown",
      Error(errors.SemanticAnalysisVendorResolutionError(
        "Unknown or unsupported vendor: unknown",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(vendor.resolve_vendor)
}
