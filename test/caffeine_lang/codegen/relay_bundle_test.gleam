import caffeine_lang/codegen/relay_bundle
import gleam/dict
import gleam/option
import gleam/string
import gleeunit/should

// ==== generate ====
// The bundle is a static set of files today. Tests pin the contract the
// downstream relay (Task #8) and the GHA workflow (Task #6) both depend on.

// * ✅ generate() always returns Some — the bundle is the same every time,
//      so gating is done by the caller in `compiler.gleam`, not here
pub fn generate_always_returns_some_test() {
  let assert option.Some(_) = relay_bundle.generate()
}

// * ✅ bundle contains gleam.toml and the src module that gleam will run by default
pub fn generate_contains_expected_files_test() {
  let assert option.Some(files) = relay_bundle.generate()
  files |> dict.has_key("gleam.toml") |> should.be_true
  // Module path must match the package name so `gleam run` (no `-m`) finds it
  // — the GHA workflow invokes the relay this way.
  files
  |> dict.has_key("src/caffeine_relay.gleam")
  |> should.be_true
  files |> dict.has_key(".gitignore") |> should.be_true
}

// * ✅ gleam.toml declares the package name `caffeine_relay` so the module
//      path resolves correctly
pub fn gleam_toml_declares_package_name_test() {
  let assert option.Some(files) = relay_bundle.generate()
  let assert Ok(toml) = dict.get(files, "gleam.toml")
  toml |> string.contains("name = \"caffeine_relay\"") |> should.be_true
  toml |> string.contains("target = \"erlang\"") |> should.be_true
  // Bare-minimum dep — Task #8 may add more (httpc, json, etc.).
  toml |> string.contains("gleam_stdlib") |> should.be_true
}

// * ✅ entry module defines a `main` function so `gleam run` works
pub fn entry_module_has_main_test() {
  let assert option.Some(files) = relay_bundle.generate()
  let assert Ok(src) = dict.get(files, "src/caffeine_relay.gleam")
  src |> string.contains("pub fn main") |> should.be_true
}

// * ✅ all bundled files are non-empty (sanity check against a future
//      truncation regression)
pub fn all_files_non_empty_test() {
  let assert option.Some(files) = relay_bundle.generate()
  files
  |> dict.to_list
  |> gleam_each(fn(pair) {
    let #(_path, content) = pair
    { string.length(content) > 0 } |> should.be_true
  })
}

// Helper since gleeunit/should doesn't have an each.
fn gleam_each(items: List(a), check: fn(a) -> Nil) -> Nil {
  case items {
    [] -> Nil
    [x, ..rest] -> {
      check(x)
      gleam_each(rest, check)
    }
  }
}
