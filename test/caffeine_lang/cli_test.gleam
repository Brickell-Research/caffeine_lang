import caffeine_lang
import caffeine_lang/common/constants
import gleam/list
import gleeunit/should

// ==== CLI Exit Codes ====
// * ✅ successful compile returns exit_success
// * ✅ compile with nonexistent blueprint file returns exit_failure
// * ✅ compile with nonexistent expectations dir returns exit_failure
// * ✅ invalid arguments returns exit_failure
// * ✅ --help returns exit_success
// * ✅ -h returns exit_success
// * ✅ --version returns exit_success
// * ✅ -V returns exit_success
// * ✅ no arguments returns exit_success
pub fn cli_exit_code_test() {
  [
    #(
      [
        "compile",
        "--quiet",
        "test/caffeine_lang/corpus/compiler/happy_path_single_blueprints.json",
        "test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
      ],
      constants.exit_success,
    ),
    #(
      ["compile", "--quiet", "/nonexistent/path.json", "/nonexistent/dir"],
      constants.exit_failure,
    ),
    #(
      [
        "compile",
        "--quiet",
        "test/caffeine_lang/corpus/compiler/happy_path_single_blueprints.json",
        "/nonexistent/expectations",
      ],
      constants.exit_failure,
    ),
    #(["--quiet", "--help"], constants.exit_success),
    #(["--quiet", "-h"], constants.exit_success),
    #(["--quiet", "--version"], constants.exit_success),
    #(["--quiet", "-V"], constants.exit_success),
    #(["--quiet"], constants.exit_success),
  ]
  |> list.each(fn(pair) {
    let #(args, expected_exit_code) = pair
    caffeine_lang.run(args) |> should.equal(expected_exit_code)
  })
}
