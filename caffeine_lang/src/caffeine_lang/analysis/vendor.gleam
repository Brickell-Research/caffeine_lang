import caffeine_lang/constants
import gleam/list
import gleam/string

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
pub fn resolve_vendor(vendor_str: String) -> Result(Vendor, Nil) {
  case vendor_str {
    v if v == constants.vendor_datadog -> Ok(Datadog)
    v if v == constants.vendor_honeycomb -> Ok(Honeycomb)
    v if v == constants.vendor_dynatrace -> Ok(Dynatrace)
    v if v == constants.vendor_newrelic -> Ok(NewRelic)
    _ -> Error(Nil)
  }
}

/// Extracts the vendor from a file path by using the filename stem.
/// For example, "blueprints/datadog.caffeine" resolves to Ok(Datadog).
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
    Honeycomb -> constants.vendor_honeycomb
    Dynatrace -> constants.vendor_dynatrace
    NewRelic -> constants.vendor_newrelic
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
