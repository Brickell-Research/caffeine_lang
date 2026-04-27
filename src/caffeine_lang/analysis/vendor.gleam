import caffeine_lang/constants
import gleam/list
import gleam/string

/// Supported monitoring and observability platform vendors.
///
/// Currently only Datadog has a generator implementation. The enum exists
/// as the extension point for additional vendors: adding one requires a
/// variant here, a generator module under `codegen/`, a `Platform`
/// constructor in `codegen/platforms.gleam`, and a vendor constant in
/// `constants.gleam`.
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

/// Extracts the vendor from a file path by using the filename stem.
/// For example, "measurements/datadog.caffeine" resolves to Ok(Datadog).
@internal
pub fn resolve_vendor_from_path(path: String) -> Result(Vendor, Nil) {
  path
  |> extract_stem
  |> resolve_vendor
}

/// Converts a Vendor to its string representation.
@internal
pub fn vendor_to_string(v: Vendor) -> String {
  case v {
    Datadog -> constants.vendor_datadog
  }
}

/// Extracts the filename stem from a path (basename without extension).
fn extract_stem(path: String) -> String {
  let base = case string.split(path, "/") {
    [] -> path
    parts -> {
      let assert Ok(last) = list.last(parts)
      last
    }
  }
  case string.split(base, ".") {
    [stem, ..] -> stem
    [] -> base
  }
}
