import caffeine_cli
import caffeine_cli/exit_status_codes
import test_helpers

// ==== CLI Exit Codes ====
// * ✅ successful compile returns Success
// * ✅ compile with nonexistent blueprint file returns Failure
// * ✅ compile with nonexistent expectations dir returns Failure
// * ✅ --help returns Success (glint handles help)
// * ✅ no arguments returns Success (glint shows help)
pub fn cli_exit_code_test() {
  test_helpers.array_based_test_executor_1(
    [
      #(
        [
          "compile",
          "--quiet",
          "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_blueprints.caffeine",
          "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
        ],
        exit_status_codes.Success,
      ),
      #(
        ["compile", "--quiet", "/nonexistent/path.caffeine", "/nonexistent/dir"],
        exit_status_codes.Failure,
      ),
      #(
        [
          "compile",
          "--quiet",
          "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_blueprints.caffeine",
          "/nonexistent/expectations",
        ],
        exit_status_codes.Failure,
      ),
      #(["--help"], exit_status_codes.Success),
      #([], exit_status_codes.Success),
    ],
    caffeine_cli.run,
  )
}
