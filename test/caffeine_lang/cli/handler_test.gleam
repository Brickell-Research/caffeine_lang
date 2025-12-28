import caffeine_lang
import caffeine_lang/cli/exit_status_codes
import test_helpers

// ==== CLI Exit Codes ====
// * ✅ successful compile returns Success
// * ✅ compile with nonexistent blueprint file returns Failure
// * ✅ compile with nonexistent expectations dir returns Failure
// * ✅ invalid arguments returns Failure
// * ✅ --help returns Success
// * ✅ -h returns Success
// * ✅ --version returns Success
// * ✅ -V returns Success
// * ✅ no arguments returns Success
pub fn cli_exit_code_test() {
  test_helpers.array_based_test_executor_1(
    [
      #(
        [
          "compile",
          "--quiet",
          "test/caffeine_lang/corpus/compiler/happy_path_single_blueprints.json",
          "test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
        ],
        exit_status_codes.Success,
      ),
      #(
        ["compile", "--quiet", "/nonexistent/path.json", "/nonexistent/dir"],
        exit_status_codes.Failure,
      ),
      #(
        [
          "compile",
          "--quiet",
          "test/caffeine_lang/corpus/compiler/happy_path_single_blueprints.json",
          "/nonexistent/expectations",
        ],
        exit_status_codes.Failure,
      ),
      #(["--quiet", "--help"], exit_status_codes.Success),
      #(["--quiet", "-h"], exit_status_codes.Success),
      #(["--quiet", "--version"], exit_status_codes.Success),
      #(["--quiet", "-V"], exit_status_codes.Success),
      #(["--quiet"], exit_status_codes.Success),
    ],
    caffeine_lang.run,
  )
}
