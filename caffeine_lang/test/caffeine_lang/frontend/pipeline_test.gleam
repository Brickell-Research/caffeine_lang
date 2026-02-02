import caffeine_lang/frontend/pipeline
import caffeine_lang/linker/artifacts.{SLO}
import caffeine_lang/source_file.{type SourceFile, SourceFile}
import gleam/dict
import gleam/list
import gleeunit/should
import simplifile

const corpus_dir = "test/caffeine_lang/corpus/frontend/pipeline"

fn read_source_file(path: String) -> SourceFile {
  let assert Ok(content) = simplifile.read(path)
  SourceFile(path: path, content: content)
}

// ==== compile_blueprints ====
// * ✅ simple blueprints source compiles to typed blueprints
pub fn compile_blueprints_test() {
  let source = read_source_file(corpus_dir <> "/simple_blueprints.caffeine")
  let assert Ok(blueprints) = pipeline.compile_blueprints(source)

  list.length(blueprints) |> should.equal(1)
  let assert Ok(bp) = list.first(blueprints)
  bp.name |> should.equal("api_availability")
  bp.artifact_refs |> should.equal([SLO])
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
  exp.blueprint_ref |> should.equal("api_availability")
  { dict.size(exp.inputs) > 0 } |> should.be_true
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
