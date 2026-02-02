import caffeine_lsp/code_actions
import caffeine_lsp/completion
import caffeine_lsp/definition
import caffeine_lsp/diagnostics
import caffeine_lsp/document_symbols
import caffeine_lsp/file_utils
import caffeine_lsp/hover
import caffeine_lsp/keyword_info
import caffeine_lsp/position_utils
import caffeine_lsp/semantic_tokens
import gleam/list
import gleam/option
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
      |> should.equal("Undefined extendable '_nonexistent' referenced by 'api'")
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
      |> should.equal("Undefined type alias '_undefined' referenced by 'test'")
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

// ==========================================================================
// Hover tests
// ==========================================================================

pub fn hover_builtin_type_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  case hover.get_hover(source, 2, 20) {
    option.Some(markdown) -> {
      { string.contains(markdown, "String") } |> should.be_true()
    }
    option.None -> should.fail()
  }
}

pub fn hover_keyword_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  case hover.get_hover(source, 0, 3) {
    option.Some(markdown) -> {
      { string.contains(markdown, "Blueprints") } |> should.be_true()
    }
    option.None -> should.fail()
  }
}

pub fn hover_empty_space_returns_none_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  hover.get_hover(source, 0, 10)
  |> should.equal(option.None)
}

pub fn hover_extendable_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }\n\nExpectations for \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides { status: true }\n"
  case hover.get_hover(source, 0, 2) {
    option.Some(markdown) -> {
      { string.contains(markdown, "_defaults") } |> should.be_true()
      { string.contains(markdown, "Provides") } |> should.be_true()
    }
    option.None -> should.fail()
  }
}

pub fn hover_type_alias_test() {
  let source =
    "_env (Type): String { x | x in { \"prod\", \"staging\" } }\n\nBlueprints for \"SLO\"\n  * \"api\":\n    Requires { env: _env }\n    Provides { value: \"x\" }\n"
  // Hover on _env in the definition
  case hover.get_hover(source, 0, 1) {
    option.Some(markdown) -> {
      { string.contains(markdown, "_env") } |> should.be_true()
      { string.contains(markdown, "Type alias") } |> should.be_true()
    }
    option.None -> should.fail()
  }
}

// ==========================================================================
// Completion tests
// ==========================================================================

pub fn completion_returns_items_test() {
  let items = completion.get_completions("", 0, 0)
  { items != [] } |> should.be_true()
}

pub fn completion_includes_keywords_test() {
  let items = completion.get_completions("", 0, 0)
  let has_blueprints = list.any(items, fn(item) { item.label == "Blueprints" })
  has_blueprints |> should.be_true()
}

pub fn completion_extends_context_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }\n\nBlueprints for \"SLO\"\n  * \"api\" extends [_defaults]:\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  // Line 3 (0-indexed), cursor inside "extends [_defaults]"
  let items = completion.get_completions(source, 3, 22)
  let has_defaults = list.any(items, fn(item) { item.label == "_defaults" })
  has_defaults |> should.be_true()
}

pub fn completion_type_context_test() {
  let source = "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: "
  // After the colon
  let items = completion.get_completions(source, 2, 21)
  // Should include type names but not keywords like "Blueprints"
  let has_string = list.any(items, fn(item) { item.label == "String" })
  has_string |> should.be_true()
}

pub fn completion_includes_extendables_test() {
  let source =
    "_base (Provides): { vendor: \"datadog\" }\n\nBlueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let items = completion.get_completions(source, 4, 0)
  let has_base = list.any(items, fn(item) { item.label == "_base" })
  has_base |> should.be_true()
}

// ==========================================================================
// Document symbols tests
// ==========================================================================

pub fn document_symbols_empty_test() {
  document_symbols.get_symbols("")
  |> should.equal([])
}

pub fn document_symbols_blueprints_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let symbols = document_symbols.get_symbols(source)
  { symbols != [] } |> should.be_true()
}

pub fn document_symbols_with_extendable_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }\n\nBlueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let symbols = document_symbols.get_symbols(source)
  let has_defaults = list.any(symbols, fn(s) { s.name == "_defaults" })
  has_defaults |> should.be_true()
}

pub fn document_symbols_type_alias_test() {
  let source =
    "_env (Type): String { x | x in { \"prod\", \"staging\" } }\n\nBlueprints for \"SLO\"\n  * \"api\":\n    Requires { env: _env }\n    Provides { value: \"x\" }\n"
  let symbols = document_symbols.get_symbols(source)
  let has_env = list.any(symbols, fn(s) { s.name == "_env" })
  has_env |> should.be_true()
}

pub fn document_symbols_expects_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  let symbols = document_symbols.get_symbols(source)
  { symbols != [] } |> should.be_true()
}

// ==========================================================================
// Semantic tokens tests
// ==========================================================================

pub fn semantic_tokens_empty_test() {
  semantic_tokens.get_semantic_tokens("")
  |> should.equal([])
}

pub fn semantic_tokens_produces_output_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let tokens = semantic_tokens.get_semantic_tokens(source)
  { tokens != [] } |> should.be_true()
}

pub fn semantic_tokens_multiple_of_five_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let tokens = semantic_tokens.get_semantic_tokens(source)
  // Each token is 5 integers: deltaLine, deltaStartChar, length, tokenType, modifiers
  { list.length(tokens) % 5 == 0 } |> should.be_true()
}

pub fn semantic_tokens_field_order_test() {
  // "Blueprints" is at line 0, col 0, length 10, type 0 (keyword), mods 0
  // The first 5 values should be: [0, 0, 10, 0, 0]
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let tokens = semantic_tokens.get_semantic_tokens(source)
  case tokens {
    [dl, dc, len, tt, mods, ..] -> {
      // deltaLine = 0 (first line)
      dl |> should.equal(0)
      // deltaCol = 0 (first column)
      dc |> should.equal(0)
      // length = 10 ("Blueprints")
      len |> should.equal(10)
      // tokenType = 0 (keyword)
      tt |> should.equal(0)
      // modifiers = 0
      mods |> should.equal(0)
    }
    _ -> should.fail()
  }
}

pub fn semantic_tokens_with_comment_test() {
  let source =
    "# This is a comment\nBlueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let tokens = semantic_tokens.get_semantic_tokens(source)
  { tokens != [] } |> should.be_true()
}

// ==========================================================================
// Definition tests
// ==========================================================================

pub fn definition_extendable_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }\n\nExpectations for \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides { status: true }\n"
  // Hover on _defaults in extends list (line 3)
  case definition.get_definition(source, 3, 25) {
    option.Some(#(line, _col, _len)) -> {
      // Should point to line 0 where _defaults is defined
      line |> should.equal(0)
    }
    option.None -> should.fail()
  }
}

pub fn definition_type_alias_test() {
  let source =
    "_env (Type): String { x | x in { \"prod\", \"staging\" } }\n\nBlueprints for \"SLO\"\n  * \"api\":\n    Requires { env: _env }\n    Provides { value: \"x\" }\n"
  // Hover on _env in Requires (line 4)
  case definition.get_definition(source, 4, 20) {
    option.Some(#(line, _col, _len)) -> {
      // Should point to line 0 where _env is defined
      line |> should.equal(0)
    }
    option.None -> should.fail()
  }
}

pub fn definition_not_found_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  // "for" is a keyword, not a definition
  definition.get_definition(source, 0, 12)
  |> should.equal(option.None)
}

pub fn definition_empty_space_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  definition.get_definition(source, 0, 10)
  |> should.equal(option.None)
}

// ==========================================================================
// Code action tests
// ==========================================================================

pub fn code_actions_quoted_field_name_test() {
  let diags = [
    code_actions.ActionDiagnostic(
      line: 2,
      character: 4,
      end_line: 2,
      end_character: 9,
      message: "Field names should not be quoted. Use 'env' instead of '\"env\"'",
    ),
  ]

  let actions = code_actions.get_code_actions(diags, "file:///test.caffeine")
  { actions != [] } |> should.be_true()

  case actions {
    [action, ..] -> {
      action.title |> should.equal("Remove quotes from field name")
      action.kind |> should.equal("quickfix")
      action.is_preferred |> should.be_true()
    }
    [] -> should.fail()
  }
}

pub fn code_actions_no_matching_diagnostic_test() {
  let diags = [
    code_actions.ActionDiagnostic(
      line: 0,
      character: 0,
      end_line: 0,
      end_character: 5,
      message: "Some other error",
    ),
  ]

  let actions = code_actions.get_code_actions(diags, "file:///test.caffeine")
  actions |> should.equal([])
}

// ==========================================================================
// Position utils tests
// ==========================================================================

pub fn find_name_position_found_test() {
  let content = "line one\n_defaults here\nline three"
  position_utils.find_name_position(content, "_defaults")
  |> should.equal(#(1, 0))
}

pub fn find_name_position_not_found_test() {
  let content = "line one\nline two"
  position_utils.find_name_position(content, "_missing")
  |> should.equal(#(0, 0))
}

pub fn extract_word_at_valid_test() {
  let content = "hello world\nfoo bar_baz"
  position_utils.extract_word_at(content, 0, 0)
  |> should.equal("hello")

  position_utils.extract_word_at(content, 0, 6)
  |> should.equal("world")

  position_utils.extract_word_at(content, 1, 4)
  |> should.equal("bar_baz")
}

pub fn extract_word_at_boundary_test() {
  let content = "hello world"
  // Space between words
  position_utils.extract_word_at(content, 0, 5)
  |> should.equal("")
}

pub fn extract_word_at_out_of_bounds_test() {
  let content = "hello"
  // Negative line
  position_utils.extract_word_at(content, -1, 0)
  |> should.equal("")

  // Line beyond content
  position_utils.extract_word_at(content, 10, 0)
  |> should.equal("")
}

// ==========================================================================
// File utils tests
// ==========================================================================

pub fn file_utils_parse_blueprints_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let assert Ok(file_utils.Blueprints(_)) = file_utils.parse(source)
}

pub fn file_utils_parse_expectations_test() {
  let source =
    "Expectations for \"api\"\n  * \"checkout\":\n    Provides { status: true }\n"
  let assert Ok(file_utils.Expects(_)) = file_utils.parse(source)
}

pub fn file_utils_parse_invalid_test() {
  let source = "totally invalid {{{ source"
  file_utils.parse(source) |> should.be_error()
}

// ==========================================================================
// Keyword info tests
// ==========================================================================

pub fn keyword_info_all_keywords_test() {
  let keywords = keyword_info.all_keywords()
  list.length(keywords) |> should.equal(7)

  let names = list.map(keywords, fn(k) { k.name })
  list.contains(names, "Blueprints") |> should.be_true()
  list.contains(names, "Expectations") |> should.be_true()
  list.contains(names, "for") |> should.be_true()
  list.contains(names, "extends") |> should.be_true()
  list.contains(names, "Requires") |> should.be_true()
  list.contains(names, "Provides") |> should.be_true()
  list.contains(names, "Type") |> should.be_true()

  // All descriptions should be non-empty
  list.each(keywords, fn(k) { { k.description != "" } |> should.be_true() })
}
