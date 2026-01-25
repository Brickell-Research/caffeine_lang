import caffeine_lsp/diagnostics
import gleam/string
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

pub fn duplicate_extendable_diagnostic_test() {
  let source =
    "_base (Provides): { vendor: \"datadog\" }
_base (Requires): { env: String }

Blueprints for \"SLO\"
  * \"api\":
    Requires { threshold: Float }
    Provides { value: \"test\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(1)
      diag.message |> should.equal("Duplicate extendable '_base'")
      // Finds first occurrence of the name in source
      diag.line |> should.equal(0)
    }
    _ -> should.fail()
  }
}

pub fn undefined_extendable_diagnostic_test() {
  let source =
    "_base (Provides): { vendor: \"datadog\" }

Blueprints for \"SLO\"
  * \"api\" extends [_base, _nonexistent]:
    Requires { env: String }
    Provides { value: \"test\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(1)
      diag.message
      |> should.equal(
        "Undefined extendable '_nonexistent' referenced by 'api'",
      )
    }
    _ -> should.fail()
  }
}

pub fn duplicate_extends_reference_diagnostic_test() {
  let source =
    "_base (Provides): { vendor: \"datadog\" }

Blueprints for \"SLO\"
  * \"api\" extends [_base, _base]:
    Requires { env: String }
    Provides { value: \"test\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      // DuplicateExtendsReference is a warning
      diag.severity |> should.equal(2)
      diag.message
      |> should.equal("Duplicate extends reference '_base' in 'api'")
    }
    _ -> should.fail()
  }
}

pub fn duplicate_type_alias_diagnostic_test() {
  let source =
    "_env (Type): String { x | x in { \"production\", \"staging\" } }
_env (Type): String { x | x in { \"dev\", \"test\" } }

Blueprints for \"SLO\"
  * \"test\":
    Requires { env: _env }
    Provides { value: \"x\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(1)
      diag.message |> should.equal("Duplicate type alias '_env'")
      // Finds first occurrence of the name in source
      diag.line |> should.equal(0)
    }
    _ -> should.fail()
  }
}

pub fn undefined_type_alias_diagnostic_test() {
  let source =
    "Blueprints for \"SLO\"
  * \"test\":
    Requires { env: _undefined }
    Provides { value: \"x\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(1)
      diag.message
      |> should.equal(
        "Undefined type alias '_undefined' referenced by 'test'",
      )
    }
    _ -> should.fail()
  }
}

pub fn circular_type_alias_diagnostic_test() {
  let source =
    "_a (Type): _b
_b (Type): _a

Blueprints for \"SLO\"
  * \"test\":
    Requires { env: String }
    Provides { value: \"x\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(1)
      // Message should mention circular
      { string.contains(diag.message, "Circular type alias") }
      |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn invalid_dict_key_type_alias_diagnostic_test() {
  let source =
    "_count (Type): Integer { x | x in ( 1..100 ) }

Blueprints for \"SLO\"
  * \"test\":
    Requires { config: Dict(_count, String) }
    Provides { value: \"x\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(1)
      { string.contains(diag.message, "_count") } |> should.be_true()
      { string.contains(diag.message, "must be String-based") }
      |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn invalid_extendable_kind_expects_diagnostic_test() {
  let source =
    "_base (Requires): { env: String }

Expectations for \"api_availability\"
  * \"checkout\":
    Provides { status: true }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(1)
      diag.message
      |> should.equal("Extendable '_base' must be Provides, got Requires")
    }
    _ -> should.fail()
  }
}

pub fn valid_expects_no_diagnostics_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }

Expectations for \"api_availability\"
  * \"checkout\" extends [_defaults]:
    Provides { status: true }
"
  diagnostics.get_diagnostics(source)
  |> should.equal([])
}

pub fn extendable_overshadowing_diagnostic_test() {
  let source =
    "_defaults (Provides): { env: \"production\", threshold: 99.0 }

Expectations for \"api_availability\"
  * \"checkout\" extends [_defaults]:
    Provides { env: \"staging\", status: true }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(1)
      diag.message
      |> should.equal(
        "Field 'env' in 'checkout' overshadows field from extendable '_defaults'",
      )
    }
    _ -> should.fail()
  }
}
