import caffeine_lang/common/errors
import gleam/string

pub type Vendor {
  Datadog
}

pub fn resolve_vendor(vendor: String) -> Result(Vendor, errors.SemanticError) {
  case { vendor |> string.lowercase |> string.trim } {
    "datadog" -> Ok(Datadog)
    _ ->
      Error(errors.VendorResolutionError(
        "Unknown or unsupported vendor: " <> vendor,
      ))
  }
}

pub fn vendor_to_string(vendor: Vendor) -> String {
  case vendor {
    Datadog -> "datadog"
  }
}
