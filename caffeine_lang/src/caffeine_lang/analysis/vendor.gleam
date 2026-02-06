import caffeine_lang/constants

/// Supported monitoring and observability platform vendors.
pub type Vendor {
  Datadog
  Honeycomb
  Dynatrace
  NewRelic
}

/// Parses a vendor string and returns the corresponding Vendor type.
/// Returns Error(Nil) for unrecognized vendor strings.
@internal
pub fn resolve_vendor(vendor: String) -> Result(Vendor, Nil) {
  case vendor {
    v if v == constants.vendor_datadog -> Ok(Datadog)
    v if v == constants.vendor_honeycomb -> Ok(Honeycomb)
    v if v == constants.vendor_dynatrace -> Ok(Dynatrace)
    v if v == constants.vendor_newrelic -> Ok(NewRelic)
    _ -> Error(Nil)
  }
}
