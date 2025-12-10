import caffeine_lang/compiler
import gleam/list
import gleeunit/should
import simplifile

fn corpus_path(file_name: String) -> String {
  "test/caffeine_lang/corpus/compiler/" <> file_name
}

// ==== Compile Test ====
// * ✅ happy path - none
// * ✅ happy path - single
// * ✅ happy path - multiple (3 SLOs across 2 teams)
pub fn compile_test() {
  [
    // happy path - none
    #(
      corpus_path("happy_path_no_expectations_blueprints.json"),
      corpus_path("happy_path_no_expectations"),
      corpus_path("happy_path_no_expectations_output.tf"),
    ),
    // happy path - single
    #(
      corpus_path("happy_path_single_blueprints.json"),
      corpus_path("happy_path_single_expectations"),
      corpus_path("happy_path_single_output.tf"),
    ),
    // happy path - multiple (3 SLOs across 2 teams)
    #(
      corpus_path("happy_path_multiple_blueprints.json"),
      corpus_path("happy_path_multiple_expectations"),
      corpus_path("happy_path_multiple_output.tf"),
    ),
  ]
  |> list.each(fn(tuple) {
    let #(input_blueprints_path, input_expectations_dir, expected_path) = tuple
    let assert Ok(expected) = simplifile.read(expected_path)

    compiler.compile(input_blueprints_path, input_expectations_dir)
    |> should.equal(Ok(expected))
  })
}
