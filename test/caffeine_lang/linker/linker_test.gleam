import caffeine_lang/analysis/vendor
import caffeine_lang/linker/linker
import caffeine_lang/source_file.{
  type VendorMeasurementSource, SourceFile, VendorMeasurementSource,
}
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
import gleeunit/should
import simplifile

const corpus_dir = "test/caffeine_lang/corpus/compiler"

fn read_source_file(path: String) -> source_file.SourceFile(a) {
  let assert Ok(content) = simplifile.read(path)
  SourceFile(path: path, content: content)
}

fn read_vendor_measurement(
  path: String,
  v: vendor.Vendor,
) -> VendorMeasurementSource {
  VendorMeasurementSource(source: read_source_file(path), vendor: v)
}

// ==== link ====
// * ✅ happy path - valid measurement + expectations produces IRs
// * ✅ invalid measurement source returns error
// * ✅ invalid expectation source returns error

pub fn link_happy_path_test() {
  let measurements = [
    read_vendor_measurement(
      corpus_dir <> "/happy_path_single_measurements.caffeine",
      vendor.Datadog,
    ),
  ]
  let expectations = [
    read_source_file(
      corpus_dir
      <> "/happy_path_single_expectations/acme/payments/slos.caffeine",
    ),
  ]

  let result =
    linker.link(
      measurements,
      expectations,
      slo_params: stdlib_artifacts.slo_params(),
    )
  result |> should.be_ok()

  let assert Ok(irs) = result
  { irs != [] } |> should.be_true()
}

pub fn link_invalid_measurement_test() {
  let measurements = [
    VendorMeasurementSource(
      source: SourceFile(path: "test.caffeine", content: "invalid source {"),
      vendor: vendor.Datadog,
    ),
  ]
  let result =
    linker.link(measurements, [], slo_params: stdlib_artifacts.slo_params())
  result |> should.be_error()
}

pub fn link_invalid_expectation_test() {
  let measurements = [
    read_vendor_measurement(
      corpus_dir <> "/happy_path_single_measurements.caffeine",
      vendor.Datadog,
    ),
  ]
  let bad_expectation =
    SourceFile(
      path: "acme/payments/bad.caffeine",
      content: "Expectations measured by invalid {",
    )

  let result =
    linker.link(
      measurements,
      [bad_expectation],
      slo_params: stdlib_artifacts.slo_params(),
    )
  result |> should.be_error()
}
