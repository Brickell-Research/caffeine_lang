import caffeine_lang/common/constants
import caffeine_lang/common/errors.{
  type CompilationError, SemanticAnalysisVendorResolutionError,
}
import gleam/string

/// Supported monitoring and observability platform vendors.
pub type Vendor {
  Datadog
}

/// Parses a vendor string and returns the corresponding Vendor type.
@internal
pub fn resolve_vendor(vendor: String) -> Result(Vendor, CompilationError) {
  case { vendor |> string.lowercase |> string.trim } {
    "datadog" -> Ok(Datadog)
    _ ->
      Error(SemanticAnalysisVendorResolutionError(
        msg: "Unknown or unsupported vendor: " <> vendor,
      ))
  }
}

/// Converts a Vendor type to its string representation.
@internal
pub fn vendor_to_string(vendor: Vendor) -> String {
  case vendor {
    Datadog -> constants.vendor_datadog
  }
}
