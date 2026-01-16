import caffeine_lang/frontend/pipeline
import gleam/string
import gleeunit/should

const corpus_dir = "test/caffeine_lang/corpus/frontend/pipeline"

// ==== compile_blueprints_file ====
// * Simple blueprints file compiles to valid JSON
pub fn compile_blueprints_file_test() {
  let assert Ok(json) =
    pipeline.compile_blueprints_file(corpus_dir <> "/simple_blueprints.caffeine")

  // Verify JSON contains expected content
  json |> string.contains("\"blueprints\"") |> should.be_true
  json |> string.contains("\"api_availability\"") |> should.be_true
  json |> string.contains("\"artifact_refs\"") |> should.be_true
  json |> string.contains("\"params\"") |> should.be_true
  json |> string.contains("\"inputs\"") |> should.be_true
}

// ==== compile_expects_file ====
// * Simple expects file compiles to valid JSON
pub fn compile_expects_file_test() {
  let assert Ok(json) =
    pipeline.compile_expects_file(corpus_dir <> "/simple_expects.caffeine")

  // Verify JSON contains expected content
  json |> string.contains("\"expectations\"") |> should.be_true
  json |> string.contains("\"checkout_availability\"") |> should.be_true
  json |> string.contains("\"blueprint_ref\"") |> should.be_true
  json |> string.contains("\"inputs\"") |> should.be_true
}

// ==== compile_blueprints_file error cases ====
// * Nonexistent file returns error
pub fn compile_blueprints_file_nonexistent_test() {
  let result = pipeline.compile_blueprints_file("/nonexistent/path.caffeine")
  result |> should.be_error
}

// ==== compile_expects_file error cases ====
// * Nonexistent file returns error
pub fn compile_expects_file_nonexistent_test() {
  let result = pipeline.compile_expects_file("/nonexistent/path.caffeine")
  result |> should.be_error
}
