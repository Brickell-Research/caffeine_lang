import caffeine_lang/constants

/// Supported monitoring and observability platform vendors.
pub type Vendor {
  Datadog
  Honeycomb
}

/// Parses a vendor string and returns the corresponding Vendor type.
/// Returns Error(Nil) for unrecognized vendor strings.
@internal
pub fn resolve_vendor(vendor: String) -> Result(Vendor, Nil) {
  case vendor {
    v if v == constants.vendor_datadog -> Ok(Datadog)
    v if v == constants.vendor_honeycomb -> Ok(Honeycomb)
    _ -> Error(Nil)
  }
}
