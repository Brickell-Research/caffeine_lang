import caffeine_lsp/diagnostics
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn empty_file_no_diagnostics_test() {
  diagnostics.get_diagnostics("")
  |> should.equal([])
}

pub fn valid_blueprints_no_diagnostics_test() {
  let source =
    "Blueprints for \"SLO\"
  * \"my_slo\":
    Requires {
      env: String
    }
    Provides {
      value: \"test\"
    }
"
  diagnostics.get_diagnostics(source)
  |> should.equal([])
}

pub fn invalid_syntax_produces_diagnostic_test() {
  let source = "Blueprints for"
  let diags = diagnostics.get_diagnostics(source)
  // Should produce at least one diagnostic
  case diags {
    [first, ..] -> {
      first.severity |> should.equal(1)
      // message should be non-empty
      { first.message != "" } |> should.be_true()
    }
    [] -> should.fail()
  }
}
