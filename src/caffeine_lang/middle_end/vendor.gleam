import caffeine_lang/common/errors.{
  type CompilationError, SemanticAnalysisVendorResolutionError,
}
import gleam/string

pub type Vendor {
  Datadog
}

pub fn resolve_vendor(vendor: String) -> Result(Vendor, CompilationError) {
  case { vendor |> string.lowercase |> string.trim } {
    "datadog" -> Ok(Datadog)
    _ ->
      Error(SemanticAnalysisVendorResolutionError(
        msg: "Unknown or unsupported vendor: " <> vendor,
      ))
  }
}

pub fn vendor_to_string(vendor: Vendor) -> String {
  case vendor {
    Datadog -> "datadog"
  }
}
