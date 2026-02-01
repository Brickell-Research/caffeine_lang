import caffeine_lang/constants

/// Supported monitoring and observability platform vendors.
pub type Vendor {
  Datadog
  Honeycomb
}

/// Parses a vendor string and returns the corresponding Vendor type.
/// The vendor string is already validated by the refinement type at parse time,
/// so this function can safely assume the input is valid.
@internal
pub fn resolve_vendor(vendor: String) -> Vendor {
  case vendor {
    "datadog" -> Datadog
    "honeycomb" -> Honeycomb
    // This case should never be reached due to refinement type validation,
    // but we need exhaustive pattern matching.
    _ -> Datadog
  }
}

/// Converts a Vendor type to its string representation.
@internal
pub fn vendor_to_string(vendor: Vendor) -> String {
  case vendor {
    Datadog -> constants.vendor_datadog
    Honeycomb -> constants.vendor_honeycomb
  }
}
