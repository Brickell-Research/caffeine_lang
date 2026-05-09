import caffeine_lang/constants

/// Supported monitoring and observability platform vendors.
///
/// Currently only Datadog has a generator implementation. The enum exists
/// as the extension point for additional vendors: adding a variant here,
/// a generator module under `codegen/`, a `Platform` constructor in
/// `codegen/platforms.gleam`, and a vendor constant in `constants.gleam`.
pub type Vendor {
  Datadog
}

/// Parses a vendor string and returns the corresponding Vendor type.
/// Returns Error(Nil) for unrecognized vendor strings.
@internal
pub fn resolve_vendor(vendor_str: String) -> Result(Vendor, Nil) {
  case vendor_str {
    v if v == constants.vendor_datadog -> Ok(Datadog)
    _ -> Error(Nil)
  }
}
