import caffeine_lsp/code_actions
import caffeine_lsp/completion
import caffeine_lsp/definition
import caffeine_lsp/diagnostics
import caffeine_lsp/document_symbols
import caffeine_lsp/file_utils
import caffeine_lsp/folding_range
import caffeine_lsp/highlight
import caffeine_lsp/hover
import caffeine_lsp/keyword_info
import caffeine_lsp/linked_editing_range
import caffeine_lsp/lsp_types
import caffeine_lsp/position_utils
import caffeine_lsp/references
import caffeine_lsp/rename
import caffeine_lsp/selection_range.{type SelectionRange, HasParent, NoParent}
import caffeine_lsp/semantic_tokens
import caffeine_lsp/type_hierarchy.{BlueprintKind, ExpectationKind}
import caffeine_lsp/workspace_symbols
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
  let items = completion.get_completions("", 0, 0, [])
  { items != [] } |> should.be_true()
}

pub fn completion_includes_keywords_test() {
  let items = completion.get_completions("", 0, 0, [])
  let has_blueprints = list.any(items, fn(item) { item.label == "Blueprints" })
  has_blueprints |> should.be_true()
}

pub fn completion_extends_context_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }\n\nBlueprints for \"SLO\"\n  * \"api\" extends [_defaults]:\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  // Line 3 (0-indexed), cursor inside "extends [_defaults]"
  let items = completion.get_completions(source, 3, 22, [])
  let has_defaults = list.any(items, fn(item) { item.label == "_defaults" })
  has_defaults |> should.be_true()
}

pub fn completion_type_context_test() {
  let source = "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: "
  // After the colon
  let items = completion.get_completions(source, 2, 21, [])
  // Should include type names but not keywords like "Blueprints"
  let has_string = list.any(items, fn(item) { item.label == "String" })
  has_string |> should.be_true()
}

pub fn completion_includes_extendables_test() {
  let source =
    "_base (Provides): { vendor: \"datadog\" }\n\nBlueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let items = completion.get_completions(source, 4, 0, [])
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

// ==== semantic_token_type_to_int ====
// * ensures indices match the token_types legend in semantic_tokens.gleam
pub fn semantic_token_type_indices_match_legend_test() {
  let all_types = [
    lsp_types.SttKeyword, lsp_types.SttType, lsp_types.SttString,
    lsp_types.SttNumber, lsp_types.SttVariable, lsp_types.SttComment,
    lsp_types.SttOperator, lsp_types.SttProperty, lsp_types.SttFunction,
    lsp_types.SttModifier, lsp_types.SttEnumMember,
  ]
  // Verify the legend has the expected length
  list.length(semantic_tokens.token_types)
  |> should.equal(list.length(all_types))
  // Verify each type's string matches its position in the legend
  semantic_tokens.token_types
  |> list.index_map(fn(name, i) { #(name, i) })
  |> list.each(fn(pair) {
    let name = pair.0
    let index = pair.1
    let assert Ok(stt) =
      list.find(all_types, fn(t) {
        lsp_types.semantic_token_type_to_string(t) == name
      })
    lsp_types.semantic_token_type_to_int(stt)
    |> should.equal(index)
  })
}

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

// ==== boolean literals ====
// * true/false tokenized as keyword (type index 0)
pub fn semantic_tokens_boolean_as_keyword_test() {
  // "true" appears as a literal in Provides
  let source =
    "Expectations for \"api\"\n  * \"checkout\":\n    Provides { status: true }\n"
  let tokens = semantic_tokens.get_semantic_tokens(source)
  // Find a token with length 4 (true) and type 0 (keyword)
  let has_true_keyword = find_token_with_type_and_length(tokens, 0, 4)
  has_true_keyword |> should.be_true()
}

// ==== colon as operator ====
// * colon tokenized as operator (type index 6)
pub fn semantic_tokens_colon_as_operator_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let tokens = semantic_tokens.get_semantic_tokens(source)
  // Find a token with length 1 and type 6 (operator)
  let has_colon_operator = find_token_with_type_and_length(tokens, 6, 1)
  has_colon_operator |> should.be_true()
}

/// Check if the encoded token data contains a token with a given type and length.
fn find_token_with_type_and_length(
  tokens: List(Int),
  token_type: Int,
  length: Int,
) -> Bool {
  find_token_loop(tokens, token_type, length)
}

fn find_token_loop(tokens: List(Int), token_type: Int, length: Int) -> Bool {
  case tokens {
    [_, _, len, tt, _, ..rest] ->
      case tt == token_type && len == length {
        True -> True
        False -> find_token_loop(rest, token_type, length)
      }
    _ -> False
  }
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
// Cross-file definition tests (blueprint ref detection)
// ==========================================================================

// ==== get_blueprint_ref_at_position ====
// * ✅ cursor on blueprint name returns the name
// * ✅ cursor in middle of name returns the name
// * ✅ cursor on last char of name returns the name
// * ✅ cursor on "Expectations" keyword returns None
// * ✅ cursor on "for" keyword returns None
// * ✅ cursor on opening quote returns None
// * ✅ cursor past closing quote returns None
// * ✅ cursor on item line returns None
// * ✅ multiple blocks, cursor on second returns correct name
// * ✅ blueprints file returns None

pub fn blueprint_ref_on_name_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on 'a' of api_availability (col 18)
  definition.get_blueprint_ref_at_position(source, 0, 18)
  |> should.equal(option.Some("api_availability"))
}

pub fn blueprint_ref_middle_of_name_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on '_' between api and availability (col 21)
  definition.get_blueprint_ref_at_position(source, 0, 21)
  |> should.equal(option.Some("api_availability"))
}

pub fn blueprint_ref_last_char_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on last 'y' of api_availability (col 33)
  definition.get_blueprint_ref_at_position(source, 0, 33)
  |> should.equal(option.Some("api_availability"))
}

pub fn blueprint_ref_on_keyword_returns_none_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on "Expectations" (col 5)
  definition.get_blueprint_ref_at_position(source, 0, 5)
  |> should.equal(option.None)
}

pub fn blueprint_ref_on_for_returns_none_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on "for" (col 14)
  definition.get_blueprint_ref_at_position(source, 0, 14)
  |> should.equal(option.None)
}

pub fn blueprint_ref_on_quote_returns_none_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on opening quote (col 17)
  definition.get_blueprint_ref_at_position(source, 0, 17)
  |> should.equal(option.None)
}

pub fn blueprint_ref_past_closing_quote_returns_none_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on closing quote (col 34)
  definition.get_blueprint_ref_at_position(source, 0, 34)
  |> should.equal(option.None)
}

pub fn blueprint_ref_on_item_line_returns_none_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on item line (line 1)
  definition.get_blueprint_ref_at_position(source, 1, 7)
  |> should.equal(option.None)
}

pub fn blueprint_ref_multiple_blocks_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { threshold: 99.95 }\n\nExpectations for \"latency\"\n  * \"checkout_p99\":\n    Provides { threshold_ms: 500 }\n"
  // Cursor on "latency" in second block (line 4, col 18)
  definition.get_blueprint_ref_at_position(source, 4, 18)
  |> should.equal(option.Some("latency"))
}

pub fn blueprint_ref_blueprints_file_returns_none_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  definition.get_blueprint_ref_at_position(source, 0, 16)
  |> should.equal(option.None)
}

// ==========================================================================
// Cross-file relation ref tests (dependency go-to-definition)
// ==========================================================================

// ==== get_relation_ref_at_position ====
// * ✅ cursor on dotted path in list returns the path
// * ✅ cursor in middle of path returns the path
// * ✅ cursor outside quotes returns None
// * ✅ non-4-segment string in list returns None
// * ✅ dotted path not in list context returns None
// * ✅ empty content returns None

pub fn relation_ref_on_valid_path_test() {
  let source =
    "Expectations for \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"org.team.svc.dep\"] } }\n"
  // Line 2, cursor on 'o' of org.team.svc.dep (col 36)
  definition.get_relation_ref_at_position(source, 2, 36)
  |> should.equal(option.Some("org.team.svc.dep"))
}

pub fn relation_ref_middle_of_path_test() {
  let source =
    "Expectations for \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"org.team.svc.dep\"] } }\n"
  // Line 2, cursor on 't' of team (col 40)
  definition.get_relation_ref_at_position(source, 2, 40)
  |> should.equal(option.Some("org.team.svc.dep"))
}

pub fn relation_ref_outside_quotes_returns_none_test() {
  let source =
    "Expectations for \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"org.team.svc.dep\"] } }\n"
  // Line 2, cursor on '[' (col 34) — outside quotes
  definition.get_relation_ref_at_position(source, 2, 34)
  |> should.equal(option.None)
}

pub fn relation_ref_non_dependency_string_returns_none_test() {
  let source =
    "Expectations for \"bp\"\n  * \"item\":\n    Provides { tags: [\"not_a_path\"] }\n"
  // Cursor inside "not_a_path" — not a 4-segment dotted path
  definition.get_relation_ref_at_position(source, 2, 23)
  |> should.equal(option.None)
}

pub fn relation_ref_not_in_list_returns_none_test() {
  // Dotted path in a plain field value (no list brackets)
  let source = "    Provides { name: \"org.team.svc.dep\" }\n"
  definition.get_relation_ref_at_position(source, 0, 22)
  |> should.equal(option.None)
}

pub fn relation_ref_empty_content_returns_none_test() {
  definition.get_relation_ref_at_position("", 0, 0)
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
      code: diagnostics.QuotedFieldName,
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
      code: diagnostics.NoDiagnosticCode,
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

pub fn find_name_position_empty_name_test() {
  let content = "Expectations for \"\"\n  * \"slo\":\n    Provides { x: true }"
  // Empty name must not hang (JS target: split_once matches empty string at pos 0)
  position_utils.find_name_position(content, "")
  |> should.equal(#(0, 0))
}

pub fn find_all_name_positions_empty_name_test() {
  let content = "hello world"
  // Empty name must not hang
  position_utils.find_all_name_positions(content, "")
  |> should.equal([])
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
  case file_utils.parse(source) {
    Ok(file_utils.Blueprints(_)) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn file_utils_parse_expectations_test() {
  let source =
    "Expectations for \"api\"\n  * \"checkout\":\n    Provides { status: true }\n"
  case file_utils.parse(source) {
    Ok(file_utils.Expects(_)) -> should.be_true(True)
    _ -> should.fail()
  }
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

// ==========================================================================
// find_all_name_positions tests
// ==========================================================================

// ==== find_all_name_positions ====
// * multiple occurrences across lines
// * not found returns empty list
// * skips partial word matches

pub fn find_all_name_positions_multiple_test() {
  let content = "_defaults here\nuses _defaults\n_defaults again"
  let positions = position_utils.find_all_name_positions(content, "_defaults")
  positions
  |> should.equal([#(0, 0), #(1, 5), #(2, 0)])
}

pub fn find_all_name_positions_not_found_test() {
  let content = "line one\nline two"
  position_utils.find_all_name_positions(content, "_missing")
  |> should.equal([])
}

pub fn find_all_name_positions_skips_partial_test() {
  let content = "_defaults_extra\n_defaults here"
  let positions = position_utils.find_all_name_positions(content, "_defaults")
  // Should only match the whole word on line 1, not the partial on line 0
  positions
  |> should.equal([#(1, 0)])
}

// ==========================================================================
// Document highlight tests
// ==========================================================================

// ==== get_highlights ====
// * extendable name highlights at definition and usages
// * non-symbol (keyword) returns empty list
// * empty space returns empty list

pub fn highlight_extendable_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }\n\nExpectations for \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides { status: true }\n"
  let highlights = highlight.get_highlights(source, 0, 2)
  // Should find _defaults at definition (line 0) and usage (line 3)
  { list.length(highlights) >= 2 } |> should.be_true()
  // First highlight should be at line 0
  case highlights {
    [#(0, 0, 9), ..] -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn highlight_keyword_returns_empty_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  // "Blueprints" is a keyword, not a defined symbol
  highlight.get_highlights(source, 0, 3)
  |> should.equal([])
}

pub fn highlight_empty_space_returns_empty_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  // Space between words
  highlight.get_highlights(source, 0, 10)
  |> should.equal([])
}

// ==========================================================================
// References tests
// ==========================================================================

// ==== get_references ====
// * extendable references at definition and usages
// * type alias references
// * non-symbol returns empty list

pub fn references_extendable_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }\n\nExpectations for \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides { status: true }\n"
  let refs = references.get_references(source, 0, 2)
  { list.length(refs) >= 2 } |> should.be_true()
}

pub fn references_type_alias_test() {
  let source =
    "_env (Type): String { x | x in { \"prod\", \"staging\" } }\n\nBlueprints for \"SLO\"\n  * \"api\":\n    Requires { env: _env }\n    Provides { value: \"x\" }\n"
  let refs = references.get_references(source, 0, 1)
  // Should find _env at definition and usage
  { list.length(refs) >= 2 } |> should.be_true()
}

pub fn references_non_symbol_returns_empty_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  references.get_references(source, 0, 3)
  |> should.equal([])
}

// ==== get_references (blueprint names) ====
// * blueprint item name returns references within same file
// * expects blueprint reference returns references

pub fn references_blueprint_item_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  // Cursor on "api" (line 1, col 5 is the 'a' in api)
  let refs = references.get_references(source, 1, 5)
  { list.length(refs) >= 1 }
  |> should.be_true()
}

pub fn references_expects_blueprint_name_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on "api_availability" (line 0, col 18)
  let refs = references.get_references(source, 0, 18)
  { list.length(refs) >= 1 }
  |> should.be_true()
}

// ==== get_blueprint_name_at ====
// * returns item name when cursor is on blueprint item
// * returns blueprint name when cursor is on Expectations for header
// * returns empty string when cursor is on keyword
// * returns empty string when cursor is on field value

pub fn get_blueprint_name_at_item_name_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  // Cursor on "api" (line 1, col 5)
  references.get_blueprint_name_at(source, 1, 5)
  |> should.equal("api")
}

pub fn get_blueprint_name_at_expects_header_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on "api_availability" (line 0, col 18)
  references.get_blueprint_name_at(source, 0, 18)
  |> should.equal("api_availability")
}

pub fn get_blueprint_name_at_keyword_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  // Cursor on "Blueprints" keyword (line 0, col 3)
  references.get_blueprint_name_at(source, 0, 3)
  |> should.equal("")
}

pub fn get_blueprint_name_at_field_value_test() {
  let source =
    "Expectations for \"api\"\n  * \"checkout\":\n    Provides { vendor: \"datadog\" }\n"
  // Cursor on "datadog" -- this is a field value, not a blueprint name
  references.get_blueprint_name_at(source, 2, 26)
  |> should.equal("")
}

// ==== find_references_to_name ====
// * finds all occurrences of a name
// * returns empty list for non-existent name

pub fn find_references_to_name_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  let refs = references.find_references_to_name(source, "api_availability")
  refs
  |> should.equal([#(0, 18, 16)])
}

pub fn find_references_to_name_not_found_test() {
  let source =
    "Expectations for \"api\"\n  * \"checkout\":\n    Provides { status: true }\n"
  references.find_references_to_name(source, "missing")
  |> should.equal([])
}

// ==========================================================================
// Rename tests
// ==========================================================================

// ==== prepare_rename ====
// * returns range for valid symbol
// * returns None for keyword
// ==== get_rename_edits ====
// * returns all locations for a symbol
// * returns empty for keyword

pub fn prepare_rename_valid_symbol_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }\n\nExpectations for \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides { status: true }\n"
  case rename.prepare_rename(source, 0, 2) {
    option.Some(#(0, 0, 9)) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn prepare_rename_keyword_returns_none_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  rename.prepare_rename(source, 0, 3)
  |> should.equal(option.None)
}

pub fn get_rename_edits_all_locations_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }\n\nExpectations for \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides { status: true }\n"
  let edits = rename.get_rename_edits(source, 0, 2)
  { list.length(edits) >= 2 } |> should.be_true()
}

pub fn get_rename_edits_keyword_returns_empty_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  rename.get_rename_edits(source, 0, 3)
  |> should.equal([])
}

// ==========================================================================
// Folding range tests
// ==========================================================================

// ==== get_folding_ranges ====
// * blueprints file produces non-empty ranges
// * expects file produces non-empty ranges
// * empty source returns empty list

pub fn folding_ranges_blueprints_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  let ranges = folding_range.get_folding_ranges(source)
  { ranges != [] } |> should.be_true()
}

pub fn folding_ranges_expects_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }\n\nExpectations for \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides { status: true }\n"
  let ranges = folding_range.get_folding_ranges(source)
  { ranges != [] } |> should.be_true()
}

pub fn folding_ranges_empty_test() {
  folding_range.get_folding_ranges("")
  |> should.equal([])
}

// ==========================================================================
// Field completion tests
// ==========================================================================

// ==== field completion ====
// * cursor inside Provides block of item extending _defaults suggests fields
// * already-defined fields are excluded

pub fn field_completion_suggests_extended_fields_test() {
  let source =
    "_defaults (Provides): { env: \"production\", threshold: 99.0 }\n\nExpectations for \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides {\n      status: true\n      \n    }\n"
  // Line 6 is the empty line inside Provides block
  let items = completion.get_completions(source, 6, 6, [])
  // Should suggest env and threshold from _defaults (minus any already defined)
  let labels = list.map(items, fn(i) { i.label })
  // "status" is already defined, but env and threshold come from _defaults
  // "status" overshadows nothing from _defaults, so env + threshold should appear
  list.contains(labels, "env") |> should.be_true()
  list.contains(labels, "threshold") |> should.be_true()
}

pub fn field_completion_excludes_defined_fields_test() {
  let source =
    "_defaults (Provides): { env: \"production\", threshold: 99.0 }\n\nExpectations for \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides {\n      env: \"staging\"\n      \n    }\n"
  // Line 6 is the empty line inside Provides block
  let items = completion.get_completions(source, 6, 6, [])
  let labels = list.map(items, fn(i) { i.label })
  // env is already defined in Provides, should not be suggested
  list.contains(labels, "env") |> should.be_false()
  // threshold should still be suggested
  list.contains(labels, "threshold") |> should.be_true()
}

// ==========================================================================
// Selection range tests
// ==========================================================================

// ==== get_selection_range ====
// * returns nested ranges with parents
// * cursor on field line produces item parent
// * empty content returns file-level range

pub fn selection_range_nested_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  // Cursor on the Requires line (line 2)
  let sr = selection_range.get_selection_range(source, 2, 10)
  // Should have at least one parent
  case sr.parent {
    HasParent(_) -> should.be_true(True)
    NoParent -> should.fail()
  }
}

pub fn selection_range_file_scope_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Provides { value: \"x\" }\n"
  let sr = selection_range.get_selection_range(source, 0, 0)
  // Walk up to find the outermost range
  let outermost = find_outermost(sr)
  outermost.start_line |> should.equal(0)
}

fn find_outermost(sr: SelectionRange) -> SelectionRange {
  case sr.parent {
    NoParent -> sr
    HasParent(p) -> find_outermost(p)
  }
}

// ==========================================================================
// Linked editing range tests
// ==========================================================================

// ==== get_linked_editing_ranges ====
// * extendable returns all occurrences
// * non-symbol returns empty list

pub fn linked_editing_range_extendable_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }\n\nExpectations for \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides { status: true }\n"
  let ranges = linked_editing_range.get_linked_editing_ranges(source, 0, 2)
  { list.length(ranges) >= 2 } |> should.be_true()
}

pub fn linked_editing_range_non_symbol_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  linked_editing_range.get_linked_editing_ranges(source, 0, 3)
  |> should.equal([])
}

// ==========================================================================
// Hover on items and fields tests
// ==========================================================================

// ==== hover on item names ====
// * blueprint item shows extends and field counts
// * expect item shows extends and field count

pub fn hover_blueprint_item_test() {
  let source =
    "_base (Requires): { env: String }\n\nBlueprints for \"SLO\"\n  * \"api\" extends [_base]:\n    Requires { threshold: Float }\n    Provides { value: \"x\" }\n"
  // Hover on "api" — it's at col ~5 on line 3 (inside quotes so extract_word_at hits it)
  // Actually, "api" is inside quotes, so we need to place cursor on "api" without quotes
  // Let's use a simpler test — hover on item name found after parsing
  case hover.get_hover(source, 3, 7) {
    option.Some(md) -> {
      { string.contains(md, "api") } |> should.be_true()
      { string.contains(md, "Blueprint item") } |> should.be_true()
    }
    option.None -> should.fail()
  }
}

pub fn hover_expect_item_test() {
  let source =
    "Expectations for \"api\"\n  * \"checkout\":\n    Provides { status: true }\n"
  case hover.get_hover(source, 1, 7) {
    option.Some(md) -> {
      { string.contains(md, "checkout") } |> should.be_true()
      { string.contains(md, "Expectation item") } |> should.be_true()
    }
    option.None -> should.fail()
  }
}

// ==== hover on field names ====
// * field shows its value/type

pub fn hover_field_name_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  case hover.get_hover(source, 2, 16) {
    option.Some(md) -> {
      { string.contains(md, "env") } |> should.be_true()
      { string.contains(md, "Field") } |> should.be_true()
    }
    option.None -> should.fail()
  }
}

// ==========================================================================
// Extends completion filtering tests
// ==========================================================================

// ==== extends completion ====
// * filters already-used extendables

pub fn extends_completion_filters_used_test() {
  let source =
    "_base (Provides): { vendor: \"datadog\" }\n_auth (Provides): { token: \"x\" }\n\nBlueprints for \"SLO\"\n  * \"api\" extends [_base, _auth]:\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  // Cursor inside "extends [_base, _auth]" at position after "_base, "
  // Line 4: "  * "api" extends [_base, _auth]:"
  // Position 28 is right after the comma+space, before _auth
  let items = completion.get_completions(source, 4, 28, [])
  let labels = list.map(items, fn(i) { i.label })
  // _base already appears before cursor, should be filtered out
  list.contains(labels, "_base") |> should.be_false()
}

// ==========================================================================
// Cross-file diagnostics tests
// ==========================================================================

// ==== get_cross_file_diagnostics ====
// * expects file with known blueprint returns no diagnostics
// * expects file with unknown blueprint returns diagnostic
// * blueprints file returns no diagnostics
// * empty content returns no diagnostics
// * multiple expects blocks with mix of known and unknown

pub fn cross_file_known_blueprint_no_diagnostics_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  diagnostics.get_cross_file_diagnostics(source, ["api_availability"])
  |> should.equal([])
}

pub fn cross_file_unknown_blueprint_returns_diagnostic_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  let diags =
    diagnostics.get_cross_file_diagnostics(source, ["other_blueprint"])
  case diags {
    [diag] -> {
      diag.severity |> should.equal(1)
      diag.message
      |> should.equal("Blueprint 'api_availability' not found in workspace")
      diag.code |> should.equal(diagnostics.BlueprintNotFound)
    }
    _ -> should.fail()
  }
}

pub fn cross_file_blueprints_file_returns_empty_test() {
  let source =
    "Blueprints for \"SLO\"\n  * \"api\":\n    Requires { env: String }\n    Provides { value: \"x\" }\n"
  diagnostics.get_cross_file_diagnostics(source, [])
  |> should.equal([])
}

pub fn cross_file_empty_content_returns_empty_test() {
  diagnostics.get_cross_file_diagnostics("", ["api"])
  |> should.equal([])
}

pub fn cross_file_multiple_blocks_mixed_test() {
  let source =
    "Expectations for \"known_bp\"\n  * \"item1\":\n    Provides { a: true }\n\nExpectations for \"unknown_bp\"\n  * \"item2\":\n    Provides { b: false }\n"
  let diags = diagnostics.get_cross_file_diagnostics(source, ["known_bp"])
  case diags {
    [diag] -> {
      diag.message
      |> should.equal("Blueprint 'unknown_bp' not found in workspace")
    }
    _ -> should.fail()
  }
}

pub fn cross_file_empty_known_list_reports_all_test() {
  let source =
    "Expectations for \"my_blueprint\"\n  * \"item\":\n    Provides { status: true }\n"
  let diags = diagnostics.get_cross_file_diagnostics(source, [])
  case diags {
    [diag] -> {
      diag.message
      |> should.equal("Blueprint 'my_blueprint' not found in workspace")
    }
    _ -> should.fail()
  }
}

// ==== get_cross_file_dependency_diagnostics ====
// * ✅ known target returns no diagnostics
// * ✅ unknown target returns DependencyNotFound diagnostic
// * ✅ empty content returns no diagnostics
// * ✅ file without relations returns no diagnostics
// * ✅ multiple targets with mix of known and unknown
// * ✅ duplicate targets produce single diagnostic

pub fn dependency_known_target_no_diagnostics_test() {
  let source =
    "Expectations for \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"org.team.svc.dep\"] } }\n"
  diagnostics.get_cross_file_dependency_diagnostics(source, [
    "org.team.svc.dep",
  ])
  |> should.equal([])
}

pub fn dependency_unknown_target_returns_diagnostic_test() {
  let source =
    "Expectations for \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"org.team.svc.dep\"] } }\n"
  let diags = diagnostics.get_cross_file_dependency_diagnostics(source, [])
  case diags {
    [diag] -> {
      diag.severity |> should.equal(1)
      diag.message
      |> should.equal("Dependency 'org.team.svc.dep' not found in workspace")
      diag.code |> should.equal(diagnostics.DependencyNotFound)
    }
    _ -> should.fail()
  }
}

pub fn dependency_empty_content_returns_empty_test() {
  diagnostics.get_cross_file_dependency_diagnostics("", [])
  |> should.equal([])
}

pub fn dependency_no_relations_returns_empty_test() {
  let source =
    "Expectations for \"bp\"\n  * \"item\":\n    Provides { status: true }\n"
  diagnostics.get_cross_file_dependency_diagnostics(source, [])
  |> should.equal([])
}

pub fn dependency_multiple_mixed_test() {
  let source =
    "Expectations for \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"known.t.s.dep\", \"unknown.t.s.dep\"] } }\n"
  let diags =
    diagnostics.get_cross_file_dependency_diagnostics(source, [
      "known.t.s.dep",
    ])
  case diags {
    [diag] -> {
      diag.message
      |> should.equal("Dependency 'unknown.t.s.dep' not found in workspace")
    }
    _ -> should.fail()
  }
}

pub fn dependency_duplicate_targets_single_diagnostic_test() {
  let source =
    "Expectations for \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"org.t.s.dep\"], soft: [\"org.t.s.dep\"] } }\n"
  let diags = diagnostics.get_cross_file_dependency_diagnostics(source, [])
  case diags {
    [diag] -> {
      diag.message
      |> should.equal("Dependency 'org.t.s.dep' not found in workspace")
    }
    _ -> should.fail()
  }
}

// ==========================================================================
// Combined diagnostics tests (get_all_diagnostics)
// ==========================================================================

// ==== get_all_diagnostics ====
// * ✅ empty content returns no diagnostics
// * ✅ valid expects with known blueprint returns no diagnostics
// * ✅ valid expects with unknown blueprint returns BlueprintNotFound
// * ✅ expects with unknown dependency returns DependencyNotFound
// * ✅ combines validation + cross-file + dependency diagnostics
// * ✅ invalid syntax returns parse error only

pub fn all_diagnostics_empty_content_test() {
  diagnostics.get_all_diagnostics("", [], [])
  |> should.equal([])
}

pub fn all_diagnostics_valid_expects_known_blueprint_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  diagnostics.get_all_diagnostics(source, ["api_availability"], [])
  |> should.equal([])
}

pub fn all_diagnostics_unknown_blueprint_test() {
  let source =
    "Expectations for \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  let diags = diagnostics.get_all_diagnostics(source, [], [])
  let has_bp_not_found =
    list.any(diags, fn(d) {
      d.code == diagnostics.BlueprintNotFound
      && string.contains(d.message, "api_availability")
    })
  has_bp_not_found |> should.be_true()
}

pub fn all_diagnostics_unknown_dependency_test() {
  let source =
    "Expectations for \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"org.team.svc.dep\"] } }\n"
  let diags = diagnostics.get_all_diagnostics(source, ["bp"], [])
  let has_dep_not_found =
    list.any(diags, fn(d) {
      d.code == diagnostics.DependencyNotFound
      && string.contains(d.message, "org.team.svc.dep")
    })
  has_dep_not_found |> should.be_true()
}

pub fn all_diagnostics_combines_all_checks_test() {
  // Expects file with validation error (overshadowing), unknown blueprint, and unknown dep
  let source =
    "_defaults (Provides): { env: \"production\" }\n\nExpectations for \"unknown_bp\"\n  * \"item\" extends [_defaults]:\n    Provides { env: \"staging\", relations: { hard: [\"org.t.s.dep\"] } }\n"
  let diags = diagnostics.get_all_diagnostics(source, [], [])
  // Should have validation error (overshadowing), blueprint not found, and dependency not found
  let has_overshadow =
    list.any(diags, fn(d) { string.contains(d.message, "overshadows") })
  let has_bp =
    list.any(diags, fn(d) { d.code == diagnostics.BlueprintNotFound })
  let has_dep =
    list.any(diags, fn(d) { d.code == diagnostics.DependencyNotFound })
  has_overshadow |> should.be_true()
  has_bp |> should.be_true()
  has_dep |> should.be_true()
}

pub fn all_diagnostics_parse_error_test() {
  let source = "Blueprints for"
  let diags = diagnostics.get_all_diagnostics(source, [], [])
  // Should produce at least one diagnostic (parse error)
  case diags {
    [first, ..] -> {
      first.severity |> should.equal(1)
      { first.message != "" } |> should.be_true()
    }
    [] -> should.fail()
  }
}

// ==========================================================================
// Workspace symbol tests
// ==========================================================================

// ==== get_workspace_symbols ====
// * empty string returns empty list
// * blueprints file returns type aliases, extendables, and items (no fields)
// * expects file returns extendables and items (no fields)
// * invalid source returns empty list

pub fn workspace_symbols_empty_test() {
  workspace_symbols.get_workspace_symbols("")
  |> should.equal([])
}

pub fn workspace_symbols_blueprints_test() {
  let source =
    "_env (Type): String { x | x in { \"prod\", \"staging\" } }
_base (Requires): { env: String }

Blueprints for \"SLO\"
  * \"api\":
    Requires { threshold: Float }
    Provides { value: \"x\" }
"
  let symbols = workspace_symbols.get_workspace_symbols(source)
  let names = list.map(symbols, fn(s) { s.name })
  // Should include the type alias, extendable, and blueprint item
  list.contains(names, "_env") |> should.be_true()
  list.contains(names, "_base") |> should.be_true()
  list.contains(names, "api") |> should.be_true()
  // Should have exactly 3 symbols (no fields like env, threshold, value)
  list.length(symbols) |> should.equal(3)
}

pub fn workspace_symbols_expects_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }

Expectations for \"api_availability\"
  * \"checkout\":
    Provides { status: true }
  * \"payments\":
    Provides { status: true }
"
  let symbols = workspace_symbols.get_workspace_symbols(source)
  let names = list.map(symbols, fn(s) { s.name })
  // Should include extendable and expect items
  list.contains(names, "_defaults") |> should.be_true()
  list.contains(names, "checkout") |> should.be_true()
  list.contains(names, "payments") |> should.be_true()
  // Should have exactly 3 symbols (no fields like env, status)
  list.length(symbols) |> should.equal(3)
}

pub fn workspace_symbols_no_fields_test() {
  let source =
    "Blueprints for \"SLO\"
  * \"api\":
    Requires { env: String, threshold: Float }
    Provides { value: \"x\", vendor: \"datadog\" }
"
  let symbols = workspace_symbols.get_workspace_symbols(source)
  let names = list.map(symbols, fn(s) { s.name })
  // Only the blueprint item, not fields
  names |> should.equal(["api"])
}

pub fn workspace_symbols_invalid_source_test() {
  workspace_symbols.get_workspace_symbols("totally invalid {{{ source")
  |> should.equal([])
}

pub fn workspace_symbols_kind_values_test() {
  let source =
    "_env (Type): String { x | x in { \"prod\" } }
_base (Provides): { vendor: \"datadog\" }

Blueprints for \"SLO\"
  * \"api\":
    Requires { env: String }
    Provides { value: \"x\" }
"
  let symbols = workspace_symbols.get_workspace_symbols(source)
  case symbols {
    [type_alias, extendable, item] -> {
      // TypeParameter = 26, Variable = 13, Class = 5
      type_alias.kind |> should.equal(26)
      extendable.kind |> should.equal(13)
      item.kind |> should.equal(5)
    }
    _ -> should.fail()
  }
}

// ==========================================================================
// Type hierarchy tests
// ==========================================================================

// ==== prepare_type_hierarchy ====
// * blueprint item name returns BlueprintKind item
// * expect item name returns ExpectationKind item with blueprint
// * keyword returns empty list
// * empty space returns empty list
// * field name returns empty list

pub fn type_hierarchy_blueprint_item_test() {
  let source =
    "Blueprints for \"SLO\"
  * \"api\":
    Requires { env: String }
    Provides { value: \"x\" }
"
  let items = type_hierarchy.prepare_type_hierarchy(source, 1, 7)
  case items {
    [item] -> {
      item.name |> should.equal("api")
      item.kind |> should.equal(BlueprintKind)
      item.blueprint |> should.equal("")
      item.name_len |> should.equal(3)
    }
    _ -> should.fail()
  }
}

pub fn type_hierarchy_expect_item_test() {
  let source =
    "Expectations for \"api_availability\"
  * \"checkout\":
    Provides { status: true }
"
  let items = type_hierarchy.prepare_type_hierarchy(source, 1, 7)
  case items {
    [item] -> {
      item.name |> should.equal("checkout")
      item.kind |> should.equal(ExpectationKind)
      item.blueprint |> should.equal("api_availability")
      item.name_len |> should.equal(8)
    }
    _ -> should.fail()
  }
}

pub fn type_hierarchy_keyword_returns_empty_test() {
  let source =
    "Blueprints for \"SLO\"
  * \"api\":
    Requires { env: String }
    Provides { value: \"x\" }
"
  type_hierarchy.prepare_type_hierarchy(source, 0, 3)
  |> should.equal([])
}

pub fn type_hierarchy_empty_space_returns_empty_test() {
  let source =
    "Blueprints for \"SLO\"
  * \"api\":
    Requires { env: String }
    Provides { value: \"x\" }
"
  type_hierarchy.prepare_type_hierarchy(source, 0, 10)
  |> should.equal([])
}

pub fn type_hierarchy_field_name_returns_empty_test() {
  let source =
    "Blueprints for \"SLO\"
  * \"api\":
    Requires { env: String }
    Provides { value: \"x\" }
"
  // "env" is a field name, not an item name
  type_hierarchy.prepare_type_hierarchy(source, 2, 16)
  |> should.equal([])
}

pub fn type_hierarchy_multiple_expects_blocks_test() {
  let source =
    "Expectations for \"bp_one\"\n  * \"item_a\":\n    Provides { status: true }\n\nExpectations for \"bp_two\"\n  * \"item_b\":\n    Provides { active: false }\n"
  let items = type_hierarchy.prepare_type_hierarchy(source, 5, 7)
  case items {
    [item] -> {
      item.name |> should.equal("item_b")
      item.blueprint |> should.equal("bp_two")
    }
    _ -> should.fail()
  }
}

// ==========================================================================
// Cross-file blueprint completion tests
// ==========================================================================

// ==== blueprint header completion ====
// * suggests workspace blueprint names when cursor is after Expectations for "
// * filters suggestions by partial prefix
// * returns empty when no workspace names provided
// * does not trigger after closing quote

pub fn blueprint_header_completion_suggests_names_test() {
  let source = "Expectations for \""
  // Cursor right after the opening quote (line 0, col 19)
  let items =
    completion.get_completions(source, 0, 19, [
      "api_availability", "latency_slo",
    ])
  let labels = list.map(items, fn(i) { i.label })
  list.contains(labels, "api_availability") |> should.be_true()
  list.contains(labels, "latency_slo") |> should.be_true()
}

pub fn blueprint_header_completion_filters_by_prefix_test() {
  let source = "Expectations for \"api"
  // Cursor after "api" (line 0, col 22)
  let items =
    completion.get_completions(source, 0, 22, [
      "api_availability", "latency_slo",
    ])
  let labels = list.map(items, fn(i) { i.label })
  list.contains(labels, "api_availability") |> should.be_true()
  list.contains(labels, "latency_slo") |> should.be_false()
}

pub fn blueprint_header_completion_empty_without_names_test() {
  let source = "Expectations for \""
  let items = completion.get_completions(source, 0, 19, [])
  items |> should.equal([])
}

pub fn blueprint_header_completion_not_after_closing_quote_test() {
  let source = "Expectations for \"api_availability\""
  // Cursor after the closing quote — should NOT be in header context
  let items =
    completion.get_completions(source, 0, 36, ["api_availability", "other"])
  let labels = list.map(items, fn(i) { i.label })
  // Should fall through to general context, not blueprint header
  list.contains(labels, "api_availability") |> should.be_false()
}
