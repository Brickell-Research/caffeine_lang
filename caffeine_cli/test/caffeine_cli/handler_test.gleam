import caffeine_cli
import gleeunit/should

// ==== CLI Results ====
// * ✅ successful compile returns Ok
// * ✅ compile with nonexistent blueprint file returns Error
// * ✅ compile with nonexistent expectations dir returns Error
// * ✅ --help returns Ok (glint handles help)
// * ✅ --version returns Ok
// * ✅ no arguments returns Ok (glint shows help)
// * ✅ --target terraform returns Ok
// * ✅ --target opentofu returns Ok
// * ✅ --target invalid returns Error
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

  caffeine_cli.run(["--version"])
  |> should.be_ok()

  caffeine_cli.run([])
  |> should.be_ok()

  caffeine_cli.run([
    "compile",
    "--quiet",
    "--target=terraform",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_blueprints.caffeine",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
  ])
  |> should.be_ok()

  caffeine_cli.run([
    "compile",
    "--quiet",
    "--target=opentofu",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_blueprints.caffeine",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
  ])
  |> should.be_ok()

  caffeine_cli.run([
    "compile",
    "--quiet",
    "--target=invalid",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_blueprints.caffeine",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
  ])
  |> should.be_error()
}

// ==== Validate Command ====
// * ✅ successful validate returns Ok
// * ✅ validate with nonexistent blueprint file returns Error
// * ✅ validate with nonexistent expectations dir returns Error
// * ✅ validate with --target=terraform returns Ok
// * ✅ validate with --target=opentofu returns Ok
// * ✅ validate with --target=invalid returns Error
pub fn validate_exit_code_test() {
  caffeine_cli.run([
    "validate",
    "--quiet",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_blueprints.caffeine",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
  ])
  |> should.be_ok()

  caffeine_cli.run([
    "validate", "--quiet", "/nonexistent/path.caffeine", "/nonexistent/dir",
  ])
  |> should.be_error()

  caffeine_cli.run([
    "validate",
    "--quiet",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_blueprints.caffeine",
    "/nonexistent/expectations",
  ])
  |> should.be_error()

  caffeine_cli.run([
    "validate",
    "--quiet",
    "--target=terraform",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_blueprints.caffeine",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
  ])
  |> should.be_ok()

  caffeine_cli.run([
    "validate",
    "--quiet",
    "--target=opentofu",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_blueprints.caffeine",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
  ])
  |> should.be_ok()

  caffeine_cli.run([
    "validate",
    "--quiet",
    "--target=invalid",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_blueprints.caffeine",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
  ])
  |> should.be_error()
}
