import caffeine_cli
import gleam/string
import gleeunit/should

// ==== CLI Results ====
// * ✅ successful compile returns Ok
// * ✅ compile with nonexistent measurement file returns Error
// * ✅ compile with nonexistent expectations dir returns Error
// * ✅ --help returns Ok
// * ✅ --version returns Ok
// * ✅ no arguments returns Ok (shows help)
// * ✅ --target terraform returns Ok
// * ✅ --target opentofu returns Ok
// * ✅ --target invalid returns Error
pub fn cli_exit_code_test() {
  caffeine_cli.run([
    "compile",
    "--quiet",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_measurements_dir",
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
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_measurements_dir",
    "/nonexistent/expectations",
  ])
  |> should.be_error()

  caffeine_cli.run_with_output(["--help"], fn(_) { Nil })
  |> should.be_ok()

  caffeine_cli.run_with_output(["--version"], fn(_) { Nil })
  |> should.be_ok()

  caffeine_cli.run_with_output([], fn(_) { Nil })
  |> should.be_ok()

  caffeine_cli.run([
    "compile",
    "--quiet",
    "--target=terraform",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_measurements_dir",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
  ])
  |> should.be_ok()

  caffeine_cli.run([
    "compile",
    "--quiet",
    "--target=opentofu",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_measurements_dir",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
  ])
  |> should.be_ok()

  caffeine_cli.run([
    "compile",
    "--quiet",
    "--target=invalid",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_measurements_dir",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
  ])
  |> should.be_error()
}

// ==== Validate Command ====
// * ✅ successful validate returns Ok
// * ✅ validate with nonexistent measurement file returns Error
// * ✅ validate with nonexistent expectations dir returns Error
// * ✅ validate with --target=terraform returns Ok
// * ✅ validate with --target=opentofu returns Ok
// * ✅ validate with --target=invalid returns Error
pub fn validate_exit_code_test() {
  caffeine_cli.run([
    "validate",
    "--quiet",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_measurements_dir",
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
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_measurements_dir",
    "/nonexistent/expectations",
  ])
  |> should.be_error()

  caffeine_cli.run([
    "validate",
    "--quiet",
    "--target=terraform",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_measurements_dir",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
  ])
  |> should.be_ok()

  caffeine_cli.run([
    "validate",
    "--quiet",
    "--target=opentofu",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_measurements_dir",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
  ])
  |> should.be_ok()

  caffeine_cli.run([
    "validate",
    "--quiet",
    "--target=invalid",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_measurements_dir",
    "../caffeine_lang/test/caffeine_lang/corpus/compiler/happy_path_single_expectations",
  ])
  |> should.be_error()
}

// ==== Format Command ====
// * ✅ format a well-formatted file returns Ok
// * ✅ format --check on a well-formatted file returns Ok
// * ✅ format with nonexistent path returns Error
pub fn format_exit_code_test() {
  // Format a well-formatted file (should succeed, no changes)
  caffeine_cli.run([
    "format",
    "--quiet",
    "../caffeine_lang/test/caffeine_lang/corpus/frontend/formatter/already_formatted.caffeine",
  ])
  |> should.be_ok()

  // Format --check on a well-formatted file (should succeed)
  caffeine_cli.run([
    "format",
    "--quiet",
    "--check",
    "../caffeine_lang/test/caffeine_lang/corpus/frontend/formatter/already_formatted.caffeine",
  ])
  |> should.be_ok()

  // Format with nonexistent path returns Error
  caffeine_cli.run(["format", "--quiet", "/nonexistent/path.caffeine"])
  |> should.be_error()
}

// ==== Artifacts Command ====
// * ✅ artifacts returns Ok
pub fn artifacts_exit_code_test() {
  caffeine_cli.run(["artifacts", "--quiet"])
  |> should.be_ok()
}

// ==== Types Command ====
// * ✅ types returns Ok
pub fn types_exit_code_test() {
  caffeine_cli.run(["types", "--quiet"])
  |> should.be_ok()
}

// ==== LSP Command ====
// * ✅ lsp returns Error with expected message
pub fn lsp_exit_code_test() {
  let result = caffeine_cli.run(["lsp"])
  result |> should.be_error()
  let assert Error(msg) = result
  msg
  |> string.contains("main.mjs")
  |> should.be_true()
}
