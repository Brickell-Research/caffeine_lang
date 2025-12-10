import caffeine_lang_v2/common/errors
import caffeine_lang_v2/middle_end/vendor
import gleam/list
import gleeunit/should

// ==== Vendor Resolution ====
// ❌ vendor resolves
// ❌ vendor does not resolve
pub fn resolve_vendor_test() {
  [
    #("datadog", Ok(vendor.Datadog)),
    #(
      "unknown",
      Error(errors.VendorResolutionError(
        "Unknown or unsupported vendor: unknown",
      )),
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair

    vendor.resolve_vendor(input)
    |> should.equal(expected)
  })
}
