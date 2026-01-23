import caffeine_lang/common/source_file.{type SourceFile, SourceFile}
import caffeine_lang/frontend/pipeline
import gleam/string
import gleeunit/should
import simplifile

const corpus_dir = "test/caffeine_lang/corpus/frontend/pipeline"

fn read_source_file(path: String) -> SourceFile {
  let assert Ok(content) = simplifile.read(path)
  SourceFile(path: path, content: content)
}

// ==== compile_blueprints ====
// * ✅ simple blueprints source compiles to valid JSON
pub fn compile_blueprints_test() {
  let source =
    read_source_file(corpus_dir <> "/simple_blueprints.caffeine")
  let assert Ok(json) = pipeline.compile_blueprints(source)

  // Verify JSON contains expected content
  json |> string.contains("\"blueprints\"") |> should.be_true
  json |> string.contains("\"api_availability\"") |> should.be_true
  json |> string.contains("\"artifact_refs\"") |> should.be_true
  json |> string.contains("\"params\"") |> should.be_true
  json |> string.contains("\"inputs\"") |> should.be_true
}

// ==== compile_expects ====
// * ✅ simple expects source compiles to valid JSON
pub fn compile_expects_test() {
  let source =
    read_source_file(corpus_dir <> "/simple_expects.caffeine")
  let assert Ok(json) = pipeline.compile_expects(source)

  // Verify JSON contains expected content
  json |> string.contains("\"expectations\"") |> should.be_true
  json |> string.contains("\"checkout_availability\"") |> should.be_true
  json |> string.contains("\"blueprint_ref\"") |> should.be_true
  json |> string.contains("\"inputs\"") |> should.be_true
}

// ==== compile_blueprints error cases ====
// * ✅ invalid source returns parse error
pub fn compile_blueprints_invalid_source_test() {
  let source = SourceFile(path: "test.caffeine", content: "not valid caffeine")
  let result = pipeline.compile_blueprints(source)
  result |> should.be_error
}

// ==== compile_expects error cases ====
// * ✅ invalid source returns parse error
pub fn compile_expects_invalid_source_test() {
  let source = SourceFile(path: "test.caffeine", content: "not valid caffeine")
  let result = pipeline.compile_expects(source)
  result |> should.be_error
}
