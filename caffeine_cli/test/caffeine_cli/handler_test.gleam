import caffeine_cli
import gleeunit/should

// ==== CLI Results ====
// * ✅ successful compile returns Ok
// * ✅ compile with nonexistent blueprint file returns Error
// * ✅ compile with nonexistent expectations dir returns Error
// * ✅ --help returns Ok (glint handles help)
// * ✅ no arguments returns Ok (glint shows help)
pub fn cli_exit_code_test() {
  caffeine_cli.run([
    "compile",
    "--quiet",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_blueprints.caffeine",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
  ])
  |> should.be_ok()

  caffeine_cli.run([
    "compile", "--quiet", "/nonexistent/path.caffeine", "/nonexistent/dir",
  ])
  |> should.be_error()

  caffeine_cli.run([
    "compile",
    "--quiet",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_blueprints.caffeine",
    "/nonexistent/expectations",
  ])
  |> should.be_error()

  caffeine_cli.run(["--help"])
  |> should.be_ok()

  caffeine_cli.run([])
  |> should.be_ok()
}
