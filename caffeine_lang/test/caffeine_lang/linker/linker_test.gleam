import caffeine_lang/analysis/vendor
import caffeine_lang/linker/linker
import caffeine_lang/source_file.{
  type VendorBlueprintSource, SourceFile, VendorBlueprintSource,
}
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
import gleeunit/should
import simplifile

const corpus_dir = "test/caffeine_lang/corpus/compiler"

fn read_source_file(path: String) -> source_file.SourceFile(a) {
  let assert Ok(content) = simplifile.read(path)
  SourceFile(path: path, content: content)
}

fn read_vendor_blueprint(
  path: String,
  v: vendor.Vendor,
) -> VendorBlueprintSource {
  VendorBlueprintSource(source: read_source_file(path), vendor: v)
}

// ==== link ====
// * ✅ happy path - valid blueprint + expectations produces IRs
// * ✅ invalid blueprint source returns error
// * ✅ invalid expectation source returns error

pub fn link_happy_path_test() {
  let blueprints = [
    read_vendor_blueprint(
      corpus_dir <> "/happy_path_single_blueprints.caffeine",
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
      blueprints,
      expectations,
      slo_params: stdlib_artifacts.slo_params(),
    )
  result |> should.be_ok()

  let assert Ok(irs) = result
  { irs != [] } |> should.be_true()
}

pub fn link_invalid_blueprint_test() {
  let blueprints = [
    VendorBlueprintSource(
      source: SourceFile(path: "test.caffeine", content: "invalid source {"),
      vendor: vendor.Datadog,
    ),
  ]
  let result =
    linker.link(blueprints, [], slo_params: stdlib_artifacts.slo_params())
  result |> should.be_error()
}

pub fn link_invalid_expectation_test() {
  let blueprints = [
    read_vendor_blueprint(
      corpus_dir <> "/happy_path_single_blueprints.caffeine",
      vendor.Datadog,
    ),
  ]
  let bad_expectation =
    SourceFile(
      path: "acme/payments/bad.caffeine",
      content: "Expectations for invalid {",
    )

  let result =
    linker.link(
      blueprints,
      [bad_expectation],
      slo_params: stdlib_artifacts.slo_params(),
    )
  result |> should.be_error()
}
