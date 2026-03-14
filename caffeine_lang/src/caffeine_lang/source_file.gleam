import caffeine_lang/analysis/vendor.{type Vendor}

/// Marker type for measurement source files.
pub type MeasurementSource

/// Marker type for expectation source files.
pub type ExpectationSource

/// A source file with its path and content.
/// The phantom `kind` parameter distinguishes measurement from expectation sources
/// at the type level. The path is retained for error messages and metadata
/// extraction (org/team/service from directory structure).
pub type SourceFile(kind) {
  SourceFile(path: String, content: String)
}

/// A measurement source file paired with its vendor, derived from the filename.
pub type VendorMeasurementSource {
  VendorMeasurementSource(source: SourceFile(MeasurementSource), vendor: Vendor)
}
