import caffeine_lang/linker/linker
import caffeine_lang/source_file.{SourceFile}
import gleeunit/should
import simplifile

const corpus_dir = "test/caffeine_lang/corpus/compiler"

fn read_source_file(path: String) -> source_file.SourceFile {
  let assert Ok(content) = simplifile.read(path)
  SourceFile(path: path, content: content)
}

// ==== link ====
// * ✅ happy path - valid blueprint + expectations produces IRs
// * ✅ invalid blueprint source returns error
// * ✅ invalid expectation source returns error

pub fn link_happy_path_test() {
  let blueprint =
    read_source_file(corpus_dir <> "/happy_path_single_blueprints.caffeine")
  let expectations = [
    read_source_file(
      corpus_dir
      <> "/happy_path_single_expectations/acme/payments/slos.caffeine",
    ),
  ]

  let result = linker.link(blueprint, expectations)
  result |> should.be_ok()

  let assert Ok(irs) = result
  { irs != [] } |> should.be_true()
}

pub fn link_invalid_blueprint_test() {
  let blueprint = SourceFile(path: "test.caffeine", content: "invalid source {")
  let result = linker.link(blueprint, [])
  result |> should.be_error()
}

pub fn link_invalid_expectation_test() {
  let blueprint =
    read_source_file(corpus_dir <> "/happy_path_single_blueprints.caffeine")
  let bad_expectation =
    SourceFile(
      path: "acme/payments/bad.caffeine",
      content: "Expectations for invalid {",
    )

  let result = linker.link(blueprint, [bad_expectation])
  result |> should.be_error()
}
