import caffeine_lang/frontend/pipeline
import caffeine_lang/source_file.{SourceFile}
import gleam/dict
import gleam/list
import gleam/option
import gleeunit/should
import simplifile

const corpus_dir = "test/caffeine_lang/corpus/frontend/pipeline"

fn read_source_file(path: String) -> source_file.SourceFile(a) {
  let assert Ok(content) = simplifile.read(path)
  SourceFile(path: path, content: content)
}

// ==== compile_measurements ====
// * ✅ simple measurements source compiles to typed measurements
pub fn compile_measurements_test() {
  let source = read_source_file(corpus_dir <> "/simple_measurements.caffeine")
  let assert Ok(measurements) = pipeline.compile_measurements(source)

  list.length(measurements) |> should.equal(1)
  let assert Ok(bp) = list.first(measurements)
  bp.name |> should.equal("api_availability")
  { dict.size(bp.params) > 0 } |> should.be_true
  { dict.size(bp.inputs) > 0 } |> should.be_true
}

// ==== compile_expects ====
// * ✅ simple expects source compiles to typed expectations
pub fn compile_expects_test() {
  let source = read_source_file(corpus_dir <> "/simple_expects.caffeine")
  let assert Ok(expectations) = pipeline.compile_expects(source)

  list.length(expectations) |> should.equal(1)
  let assert Ok(exp) = list.first(expectations)
  exp.name |> should.equal("checkout_availability")
  exp.measurement_ref |> should.equal(option.Some("api_availability"))
  { dict.size(exp.inputs) > 0 } |> should.be_true
}

// ==== compile_measurements error cases ====
// * ✅ invalid source returns parse error
pub fn compile_measurements_invalid_source_test() {
  let source = SourceFile(path: "test.caffeine", content: "not valid caffeine")
  let result = pipeline.compile_measurements(source)
  result |> should.be_error
}

// ==== compile_expects error cases ====
// * ✅ invalid source returns parse error
pub fn compile_expects_invalid_source_test() {
  let source = SourceFile(path: "test.caffeine", content: "not valid caffeine")
  let result = pipeline.compile_expects(source)
  result |> should.be_error
}
