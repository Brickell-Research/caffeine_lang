import caffeine_lsp/code_actions
import caffeine_lsp/completion
import caffeine_lsp/definition
import caffeine_lsp/diagnostics
import caffeine_lsp/document_symbols
import caffeine_lsp/file_utils
import caffeine_lsp/folding_range
import caffeine_lsp/highlight
import caffeine_lsp/hover
import caffeine_lsp/inlay_hints
import caffeine_lsp/keyword_info
import caffeine_lsp/linked_editing_range
import caffeine_lsp/linker_diagnostics
import caffeine_lsp/lsp_types
import caffeine_lsp/position_utils
import caffeine_lsp/references
import caffeine_lsp/rename
import caffeine_lsp/selection_range.{type SelectionRange, HasParent, NoParent}
import caffeine_lsp/semantic_tokens
import caffeine_lsp/signature_help
import caffeine_lsp/type_hierarchy.{ExpectationKind, MeasurementKind}
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

pub fn valid_measurements_no_diagnostics_test() {
  let source =
    "\"my_slo\":
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
  let source = "\"test\":\n  Requires { env: Unknown }"
  let diags = diagnostics.get_diagnostics(source)
  // Should produce at least one diagnostic
  case diags {
    [first, ..] -> {
      first.severity |> should.equal(lsp_types.DsError)
      // message should be non-empty
      { first.message != "" } |> should.be_true()
    }
    [] -> should.fail()
  }
}

pub fn duplicate_extendable_diagnostic_test() {
  let source =
    "_base (Provides): {}
_base (Requires): { env: String }

\"api\":
  Requires { threshold: Float }
  Provides { value: \"test\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(lsp_types.DsError)
      diag.message |> should.equal("Duplicate extendable '_base'")
      // Finds first occurrence of the name in source
      diag.line |> should.equal(0)
    }
    _ -> should.fail()
  }
}

pub fn undefined_extendable_diagnostic_test() {
  let source =
    "_base (Provides): {}

\"api\" extends [_base, _nonexistent]:
  Requires { env: String }
  Provides { value: \"test\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(lsp_types.DsError)
      diag.message
      |> should.equal("Undefined extendable '_nonexistent' referenced by 'api'")
    }
    _ -> should.fail()
  }
}

pub fn duplicate_extends_reference_diagnostic_test() {
  let source =
    "_base (Provides): {}

\"api\" extends [_base, _base]:
  Requires { env: String }
  Provides { value: \"test\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      // DuplicateExtendsReference is a warning
      diag.severity |> should.equal(lsp_types.DsWarning)
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

\"test\":
  Requires { env: _env }
  Provides { value: \"x\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(lsp_types.DsError)
      diag.message |> should.equal("Duplicate type alias '_env'")
      // Finds first occurrence of the name in source
      diag.line |> should.equal(0)
    }
    _ -> should.fail()
  }
}

pub fn undefined_type_alias_diagnostic_test() {
  let source =
    "\"test\":
  Requires { env: _undefined }
  Provides { value: \"x\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(lsp_types.DsError)
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

\"test\":
  Requires { env: String }
  Provides { value: \"x\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(lsp_types.DsError)
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

\"test\":
  Requires { config: Dict(_count, String) }
  Provides { value: \"x\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(lsp_types.DsError)
      { string.contains(diag.message, "_count") } |> should.be_true()
      { string.contains(diag.message, "must be String-based") }
      |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn invalid_extendable_kind_expects_diagnostic_test() {
  // An expects file starting with a Requires extendable should be detected
  // as an expects file and produce an InvalidExtendableKind error.
  let source =
    "_base (Requires): { env: String }

Expectations measured by \"api_availability\"
  * \"checkout\":
    Provides { status: true }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(lsp_types.DsError)
      { string.contains(diag.message, "_base") } |> should.be_true()
      { string.contains(diag.message, "must be Provides") } |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn valid_expects_no_diagnostics_test() {
  // An expects file without extendables is correctly detected and validated.
  let source =
    "Expectations measured by \"api_availability\"
  * \"checkout\":
    Provides { status: true }
"
  diagnostics.get_diagnostics(source)
  |> should.equal([])
}

pub fn extendable_overshadowing_diagnostic_test() {
  // Overshadowing is detected in a measurements file when an item extends
  // a Provides extendable and redefines one of its fields.
  let source =
    "_defaults (Provides): { env: \"production\", threshold: 99.0 }

\"checkout\" extends [_defaults]:
  Requires { status: Boolean }
  Provides { env: \"staging\", value: \"test\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(lsp_types.DsError)
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
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  case hover.get_hover(source, 1, 18, []) {
    option.Some(markdown) -> {
      { string.contains(markdown, "String") } |> should.be_true()
    }
    option.None -> should.fail()
  }
}

pub fn hover_keyword_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  case hover.get_hover(source, 1, 4, []) {
    option.Some(markdown) -> {
      { string.contains(markdown, "Requires") } |> should.be_true()
    }
    option.None -> should.fail()
  }
}

pub fn hover_empty_space_returns_none_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  // Line 1 col 0 is the leading space before "Requires"
  hover.get_hover(source, 1, 0, [])
  |> should.equal(option.None)
}

pub fn hover_extendable_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }\n\nExpectations measured by \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides { status: true }\n"
  case hover.get_hover(source, 0, 2, []) {
    option.Some(markdown) -> {
      { string.contains(markdown, "_defaults") } |> should.be_true()
      { string.contains(markdown, "Provides") } |> should.be_true()
    }
    option.None -> should.fail()
  }
}

pub fn hover_type_alias_test() {
  let source =
    "_env (Type): String { x | x in { \"prod\", \"staging\" } }\n\n\"api\":\n  Requires { env: _env }\n  Provides { value: \"x\" }\n"
  // Hover on _env in the definition
  case hover.get_hover(source, 0, 1, []) {
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
  let items = completion.get_completions("", 0, 0, [], [])
  { items != [] } |> should.be_true()
}

pub fn completion_includes_keywords_test() {
  let items = completion.get_completions("", 0, 0, [], [])
  let has_measurements =
    list.any(items, fn(item) { item.label == "Measurements" })
  has_measurements |> should.be_true()
}

pub fn completion_extends_context_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }\n\n\"api\" extends [_defaults]:\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  // Line 3 (0-indexed), cursor inside "extends [_defaults]"
  let items = completion.get_completions(source, 2, 18, [], [])
  let has_defaults = list.any(items, fn(item) { item.label == "_defaults" })
  has_defaults |> should.be_true()
}

pub fn completion_type_context_test() {
  let source = "\"api\":\n  Requires { env: "
  // After the colon
  let items = completion.get_completions(source, 1, 19, [], [])
  // Should include type names but not keywords like "Measurements"
  let has_string = list.any(items, fn(item) { item.label == "String" })
  has_string |> should.be_true()
}

pub fn completion_includes_extendables_test() {
  let source =
    "_base (Provides): {}\n\n\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  let items = completion.get_completions(source, 3, 0, [], [])
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

pub fn document_symbols_measurements_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  let symbols = document_symbols.get_symbols(source)
  { symbols != [] } |> should.be_true()
}

pub fn document_symbols_with_extendable_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }\n\n\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  let symbols = document_symbols.get_symbols(source)
  let has_defaults = list.any(symbols, fn(s) { s.name == "_defaults" })
  has_defaults |> should.be_true()
}

pub fn document_symbols_type_alias_test() {
  let source =
    "_env (Type): String { x | x in { \"prod\", \"staging\" } }\n\n\"api\":\n  Requires { env: _env }\n  Provides { value: \"x\" }\n"
  let symbols = document_symbols.get_symbols(source)
  let has_env = list.any(symbols, fn(s) { s.name == "_env" })
  has_env |> should.be_true()
}

pub fn document_symbols_expects_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
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
    lsp_types.SttModifier,
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
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  let tokens = semantic_tokens.get_semantic_tokens(source)
  { tokens != [] } |> should.be_true()
}

pub fn semantic_tokens_multiple_of_five_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  let tokens = semantic_tokens.get_semantic_tokens(source)
  // Each token is 5 integers: deltaLine, deltaStartChar, length, tokenType, modifiers
  { list.length(tokens) % 5 == 0 } |> should.be_true()
}

pub fn semantic_tokens_field_order_test() {
  // "\"api\"" is at line 0, col 0, length 5, type 2 (string), mods 0
  // The first 5 values should be: [0, 0, 5, 2, 0]
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  let tokens = semantic_tokens.get_semantic_tokens(source)
  case tokens {
    [dl, dc, len, tt, mods, ..] -> {
      // deltaLine = 0 (first line)
      dl |> should.equal(0)
      // deltaCol = 0 (first column)
      dc |> should.equal(0)
      // length = 5 ("api")
      len |> should.equal(5)
      // tokenType = 2 (string)
      tt |> should.equal(2)
      // modifiers = 0
      mods |> should.equal(0)
    }
    _ -> should.fail()
  }
}

pub fn semantic_tokens_with_comment_test() {
  let source =
    "# This is a comment\n\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  let tokens = semantic_tokens.get_semantic_tokens(source)
  { tokens != [] } |> should.be_true()
}

// ==== boolean literals ====
// * true/false tokenized as keyword (type index 0)
pub fn semantic_tokens_boolean_as_keyword_test() {
  // "true" appears as a literal in Provides
  let source =
    "Expectations measured by \"api\"\n  * \"checkout\":\n    Provides { status: true }\n"
  let tokens = semantic_tokens.get_semantic_tokens(source)
  // Find a token with length 4 (true) and type 0 (keyword)
  let has_true_keyword = find_token_with_type_and_length(tokens, 0, 4)
  has_true_keyword |> should.be_true()
}

// ==== colon as operator ====
// * colon tokenized as operator (type index 6)
pub fn semantic_tokens_colon_as_operator_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
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
    "_defaults (Provides): { env: \"production\" }\n\nExpectations measured by \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides { status: true }\n"
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
    "_env (Type): String { x | x in { \"prod\", \"staging\" } }\n\n\"api\":\n  Requires { env: _env }\n  Provides { value: \"x\" }\n"
  // Hover on _env in Requires (line 4)
  case definition.get_definition(source, 3, 18) {
    option.Some(#(line, _col, _len)) -> {
      // Should point to line 0 where _env is defined
      line |> should.equal(0)
    }
    option.None -> should.fail()
  }
}

pub fn definition_not_found_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  // "for" is a keyword, not a definition
  definition.get_definition(source, 0, 5)
  |> should.equal(option.None)
}

pub fn definition_empty_space_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  definition.get_definition(source, 0, 5)
  |> should.equal(option.None)
}

// ==========================================================================
// Cross-file definition tests (measurement ref detection)
// ==========================================================================

// ==== get_measurement_ref_at_position ====
// * ✅ cursor on measurement name returns the name
// * ✅ cursor in middle of name returns the name
// * ✅ cursor on last char of name returns the name
// * ✅ cursor on "Expectations" keyword returns None
// * ✅ cursor on "for" keyword returns None
// * ✅ cursor on opening quote returns None
// * ✅ cursor past closing quote returns None
// * ✅ cursor on item line returns None
// * ✅ multiple blocks, cursor on second returns correct name
// * ✅ measurements file returns None

pub fn measurement_ref_on_name_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on 'a' of api_availability (col 26)
  definition.get_measurement_ref_at_position(source, 0, 26)
  |> should.equal(option.Some("api_availability"))
}

pub fn measurement_ref_middle_of_name_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on '_' between api and availability (col 29)
  definition.get_measurement_ref_at_position(source, 0, 29)
  |> should.equal(option.Some("api_availability"))
}

pub fn measurement_ref_last_char_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on last 'y' of api_availability (col 41)
  definition.get_measurement_ref_at_position(source, 0, 41)
  |> should.equal(option.Some("api_availability"))
}

pub fn measurement_ref_on_keyword_returns_none_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on "Expectations" (col 5)
  definition.get_measurement_ref_at_position(source, 0, 5)
  |> should.equal(option.None)
}

pub fn measurement_ref_on_for_returns_none_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on "measured" (col 14)
  definition.get_measurement_ref_at_position(source, 0, 14)
  |> should.equal(option.None)
}

pub fn measurement_ref_on_quote_returns_none_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on opening quote (col 25)
  definition.get_measurement_ref_at_position(source, 0, 25)
  |> should.equal(option.None)
}

pub fn measurement_ref_past_closing_quote_returns_none_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on closing quote (col 42)
  definition.get_measurement_ref_at_position(source, 0, 42)
  |> should.equal(option.None)
}

pub fn measurement_ref_on_item_line_returns_none_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on item line (line 1)
  definition.get_measurement_ref_at_position(source, 1, 7)
  |> should.equal(option.None)
}

pub fn measurement_ref_multiple_blocks_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { threshold: 99.95 }\n\nExpectations measured by \"latency\"\n  * \"checkout_p99\":\n    Provides { threshold_ms: 500 }\n"
  // Cursor on "latency" in second block (line 4, col 26)
  definition.get_measurement_ref_at_position(source, 4, 26)
  |> should.equal(option.Some("latency"))
}

pub fn measurement_ref_measurements_file_returns_none_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  definition.get_measurement_ref_at_position(source, 0, 4)
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
    "Expectations measured by \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"org.team.svc.dep\"] } }\n"
  // Line 2, cursor on 'o' of org.team.svc.dep (col 36)
  definition.get_relation_ref_at_position(source, 2, 36)
  |> should.equal(option.Some("org.team.svc.dep"))
}

pub fn relation_ref_middle_of_path_test() {
  let source =
    "Expectations measured by \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"org.team.svc.dep\"] } }\n"
  // Line 2, cursor on 't' of team (col 40)
  definition.get_relation_ref_at_position(source, 2, 40)
  |> should.equal(option.Some("org.team.svc.dep"))
}

pub fn relation_ref_outside_quotes_returns_none_test() {
  let source =
    "Expectations measured by \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"org.team.svc.dep\"] } }\n"
  // Line 2, cursor on '[' (col 34) — outside quotes
  definition.get_relation_ref_at_position(source, 2, 34)
  |> should.equal(option.None)
}

pub fn relation_ref_non_dependency_string_returns_none_test() {
  let source =
    "Expectations measured by \"bp\"\n  * \"item\":\n    Provides { tags: [\"not_a_path\"] }\n"
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
  |> should.equal(Ok(#(1, 0)))
}

pub fn find_name_position_not_found_test() {
  let content = "line one\nline two"
  position_utils.find_name_position(content, "_missing")
  |> should.equal(Error(Nil))
}

pub fn find_name_position_empty_name_test() {
  let content =
    "Expectations measured by \"\"\n  * \"slo\":\n    Provides { x: true }"
  // Empty name must not hang (JS target: split_once matches empty string at pos 0)
  position_utils.find_name_position(content, "")
  |> should.equal(Error(Nil))
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

// ==== find_block_end ====
// * ✅ finds last content line before dedent
// * ✅ returns fallback for empty input
// * ✅ skips blank lines within block
// * ✅ stops at line with indent <= parent
pub fn find_block_end_content_lines_test() {
  // Simulates lines after a block header at indent 2
  let lines = ["    field1: String", "    field2: Float", "  next_item"]
  // parent_indent=2, start_idx=5, fallback=4
  position_utils.find_block_end(lines, 2, 5, 4)
  |> should.equal(6)
}

pub fn find_block_end_empty_test() {
  position_utils.find_block_end([], 2, 0, 99)
  |> should.equal(99)
}

pub fn find_block_end_skips_blanks_test() {
  let lines = ["    field1: String", "", "    field2: Float"]
  position_utils.find_block_end(lines, 2, 0, 0)
  |> should.equal(2)
}

pub fn find_block_end_stops_at_dedent_test() {
  let lines = ["    deep", "  shallow"]
  position_utils.find_block_end(lines, 2, 10, 9)
  |> should.equal(10)
}

// ==== find_item_start_line ====
// * ✅ finds item by name
// * ✅ returns fallback when not found
// * ✅ matches exact pattern with quotes
pub fn find_item_start_line_found_test() {
  let lines = [
    "Expectations measured by \"test\"",
    "  * \"api\":",
    "    Provides { x: 1 }",
    "  * \"web\":",
    "    Provides { y: 2 }",
  ]
  position_utils.find_item_start_line(lines, "api", 99)
  |> should.equal(1)

  position_utils.find_item_start_line(lines, "web", 99)
  |> should.equal(3)
}

pub fn find_item_start_line_not_found_test() {
  let lines = ["Expectations measured by \"test\"", "  * \"api\":"]
  position_utils.find_item_start_line(lines, "missing", 42)
  |> should.equal(42)
}

pub fn find_item_start_line_partial_match_test() {
  // "api_v2" should not match "api"
  let lines = ["  * \"api_v2\":"]
  position_utils.find_item_start_line(lines, "api", 99)
  |> should.equal(99)
}

// ==== find_enclosing_item ====
// * ✅ finds enclosing item from inside provides block
// * ✅ returns None when no item above
pub fn find_enclosing_item_found_test() {
  let lines =
    string.split(
      "Expectations measured by \"test\"\n  * \"my_slo\":\n    Provides { x: 1 }",
      "\n",
    )
  // Cursor on line 2 (Provides line), should find "my_slo"
  completion.find_enclosing_item(lines, 2)
  |> should.equal(option.Some("my_slo"))
}

pub fn find_enclosing_item_none_test() {
  let lines = string.split("Expectations measured by \"test\"", "\n")
  completion.find_enclosing_item(lines, 0)
  |> should.equal(option.None)
}

// ==== find_enclosing_measurement_ref ====
// * ✅ finds enclosing measurement reference
// * ✅ returns None when no header above
pub fn find_enclosing_measurement_ref_found_test() {
  let lines =
    string.split(
      "Expectations measured by \"my_measurement\"\n  * \"item\":\n    Provides { x: 1 }",
      "\n",
    )
  completion.find_enclosing_measurement_ref(lines, 2)
  |> should.equal(option.Some("my_measurement"))
}

pub fn find_enclosing_measurement_ref_none_test() {
  let lines = string.split("# just a comment\nsome text", "\n")
  completion.find_enclosing_measurement_ref(lines, 1)
  |> should.equal(option.None)
}

// ==========================================================================
// File utils tests
// ==========================================================================

pub fn file_utils_parse_measurements_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  case file_utils.parse(source) {
    Ok(file_utils.Measurements(_)) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn file_utils_parse_expectations_test() {
  let source =
    "Expectations measured by \"api\"\n  * \"checkout\":\n    Provides { status: true }\n"
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
  list.length(keywords) |> should.equal(8)

  let names = list.map(keywords, fn(k) { k.name })
  list.contains(names, "Measurements") |> should.be_true()
  list.contains(names, "Expectations") |> should.be_true()
  list.contains(names, "measured") |> should.be_true()
  list.contains(names, "by") |> should.be_true()
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
    "_defaults (Provides): { env: \"production\" }\n\nExpectations measured by \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides { status: true }\n"
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
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  // "Measurements" is a keyword, not a defined symbol
  highlight.get_highlights(source, 1, 4)
  |> should.equal([])
}

pub fn highlight_empty_space_returns_empty_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  // Space between words
  highlight.get_highlights(source, 0, 5)
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
    "_defaults (Provides): { env: \"production\" }\n\nExpectations measured by \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides { status: true }\n"
  let refs = references.get_references(source, 0, 2)
  { list.length(refs) >= 2 } |> should.be_true()
}

pub fn references_type_alias_test() {
  let source =
    "_env (Type): String { x | x in { \"prod\", \"staging\" } }\n\n\"api\":\n  Requires { env: _env }\n  Provides { value: \"x\" }\n"
  let refs = references.get_references(source, 0, 1)
  // Should find _env at definition and usage
  { list.length(refs) >= 2 } |> should.be_true()
}

pub fn references_non_symbol_returns_empty_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  references.get_references(source, 1, 4)
  |> should.equal([])
}

// ==== get_references (measurement names) ====
// * measurement item name returns references within same file
// * expects measurement reference returns references

pub fn references_measurement_item_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  // Cursor on "api" (line 1, col 5 is the 'a' in api)
  let refs = references.get_references(source, 0, 1)
  { list.length(refs) >= 1 }
  |> should.be_true()
}

pub fn references_expects_measurement_name_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on "api_availability" (line 0, col 26)
  let refs = references.get_references(source, 0, 26)
  { list.length(refs) >= 1 }
  |> should.be_true()
}

// ==== get_measurement_name_at ====
// * returns item name when cursor is on measurement item
// * returns measurement name when cursor is on Expectations measured by header
// * returns empty string when cursor is on keyword
// * returns empty string when cursor is on field value

pub fn get_measurement_name_at_item_name_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  // Cursor on "api" (line 1, col 5)
  references.get_measurement_name_at(source, 0, 1)
  |> should.equal("api")
}

pub fn get_measurement_name_at_expects_header_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on "api_availability" (line 0, col 26)
  references.get_measurement_name_at(source, 0, 26)
  |> should.equal("api_availability")
}

pub fn get_measurement_name_at_keyword_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  // Cursor on "Measurements" keyword (line 0, col 3)
  references.get_measurement_name_at(source, 1, 4)
  |> should.equal("")
}

pub fn get_measurement_name_at_field_value_test() {
  let source =
    "Expectations measured by \"api\"\n  * \"checkout\":\n    Provides { status: true }\n"
  // Cursor on "true" -- this is a field value, not a measurement name
  references.get_measurement_name_at(source, 2, 22)
  |> should.equal("")
}

// ==== find_references_to_name ====
// * finds all occurrences of a name
// * returns empty list for non-existent name

pub fn find_references_to_name_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  let refs = references.find_references_to_name(source, "api_availability")
  refs
  |> should.equal([#(0, 26, 16)])
}

pub fn find_references_to_name_not_found_test() {
  let source =
    "Expectations measured by \"api\"\n  * \"checkout\":\n    Provides { status: true }\n"
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
    "_defaults (Provides): { env: \"production\" }\n\nExpectations measured by \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides { status: true }\n"
  case rename.prepare_rename(source, 0, 2) {
    option.Some(#(0, 0, 9)) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn prepare_rename_keyword_returns_none_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  rename.prepare_rename(source, 1, 4)
  |> should.equal(option.None)
}

pub fn get_rename_edits_all_locations_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }\n\nExpectations measured by \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides { status: true }\n"
  let edits = rename.get_rename_edits(source, 0, 2)
  { list.length(edits) >= 2 } |> should.be_true()
}

pub fn get_rename_edits_keyword_returns_empty_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  rename.get_rename_edits(source, 1, 4)
  |> should.equal([])
}

// ==========================================================================
// Folding range tests
// ==========================================================================

// ==== get_folding_ranges ====
// * measurements file produces non-empty ranges
// * expects file produces non-empty ranges
// * empty source returns empty list

pub fn folding_ranges_measurements_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  let ranges = folding_range.get_folding_ranges(source)
  { ranges != [] } |> should.be_true()
}

pub fn folding_ranges_expects_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }\n\nExpectations measured by \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides { status: true }\n"
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
    "_defaults (Provides): { env: \"production\", threshold: 99.0 }\n\n\"checkout\" extends [_defaults]:\n  Requires {}\n  Provides {\n    status: true\n    \n  }\n"
  // Line 6 is the empty line inside Provides block
  let items = completion.get_completions(source, 6, 6, [], [])
  // Should suggest env and threshold from _defaults (minus any already defined)
  let labels = list.map(items, fn(i) { i.label })
  // "status" is already defined, but env and threshold come from _defaults
  // "status" overshadows nothing from _defaults, so env + threshold should appear
  list.contains(labels, "env") |> should.be_true()
  list.contains(labels, "threshold") |> should.be_true()
}

pub fn field_completion_excludes_defined_fields_test() {
  let source =
    "_defaults (Provides): { env: \"production\", threshold: 99.0 }\n\n\"checkout\" extends [_defaults]:\n  Requires {}\n  Provides {\n    env: \"staging\"\n    \n  }\n"
  // Line 6 is the empty line inside Provides block
  let items = completion.get_completions(source, 6, 6, [], [])
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
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  // Cursor on the Requires line (line 2)
  let sr = selection_range.get_selection_range(source, 1, 10)
  // Should have at least one parent
  case sr.parent {
    HasParent(_) -> should.be_true(True)
    NoParent -> should.fail()
  }
}

pub fn selection_range_file_scope_test() {
  let source = "\"api\":\n  Provides { value: \"x\" }\n"
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
    "_defaults (Provides): { env: \"production\" }\n\nExpectations measured by \"api\"\n  * \"checkout\" extends [_defaults]:\n    Provides { status: true }\n"
  let ranges = linked_editing_range.get_linked_editing_ranges(source, 0, 2)
  { list.length(ranges) >= 2 } |> should.be_true()
}

pub fn linked_editing_range_non_symbol_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  linked_editing_range.get_linked_editing_ranges(source, 1, 4)
  |> should.equal([])
}

// ==========================================================================
// Hover on items and fields tests
// ==========================================================================

// ==== hover on item names ====
// * measurement item shows extends and field counts
// * expect item shows extends and field count

pub fn hover_measurement_item_test() {
  let source =
    "_base (Requires): { env: String }\n\n\"api\" extends [_base]:\n  Requires { threshold: Float }\n  Provides { value: \"x\" }\n"
  // Hover on "api" — it's at col ~5 on line 3 (inside quotes so extract_word_at hits it)
  // Actually, "api" is inside quotes, so we need to place cursor on "api" without quotes
  // Let's use a simpler test — hover on item name found after parsing
  case hover.get_hover(source, 2, 3, []) {
    option.Some(md) -> {
      { string.contains(md, "api") } |> should.be_true()
      { string.contains(md, "Measurement item") } |> should.be_true()
    }
    option.None -> should.fail()
  }
}

pub fn hover_expect_item_test() {
  let source =
    "Expectations measured by \"api\"\n  * \"checkout\":\n    Provides { status: true }\n"
  case hover.get_hover(source, 1, 7, []) {
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
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  case hover.get_hover(source, 1, 14, []) {
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
    "_base (Provides): {}\n_auth (Provides): { token: \"x\" }\n\n\"api\" extends [_base, _auth]:\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  // Cursor inside "extends [_base, _auth]" at position after "_base, "
  // Line 4: "  * "api" extends [_base, _auth]:"
  // Position 28 is right after the comma+space, before _auth
  let items = completion.get_completions(source, 3, 24, [], [])
  let labels = list.map(items, fn(i) { i.label })
  // _base already appears before cursor, should be filtered out
  list.contains(labels, "_base") |> should.be_false()
}

// ==========================================================================
// Cross-file diagnostics tests
// ==========================================================================

// ==== get_cross_file_diagnostics ====
// * expects file with known measurement returns no diagnostics
// * expects file with unknown measurement returns diagnostic
// * measurements file returns no diagnostics
// * empty content returns no diagnostics
// * multiple expects blocks with mix of known and unknown

pub fn cross_file_known_measurement_no_diagnostics_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  diagnostics.get_cross_file_diagnostics(source, ["api_availability"])
  |> should.equal([])
}

pub fn cross_file_unknown_measurement_returns_diagnostic_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  let diags =
    diagnostics.get_cross_file_diagnostics(source, ["other_measurement"])
  case diags {
    [diag] -> {
      diag.severity |> should.equal(lsp_types.DsError)
      diag.message
      |> should.equal("Measurement 'api_availability' not found in workspace")
      diag.code |> should.equal(diagnostics.MeasurementNotFound)
    }
    _ -> should.fail()
  }
}

pub fn cross_file_measurements_file_returns_empty_test() {
  let source =
    "\"api\":\n  Requires { env: String }\n  Provides { value: \"x\" }\n"
  diagnostics.get_cross_file_diagnostics(source, [])
  |> should.equal([])
}

pub fn cross_file_empty_content_returns_empty_test() {
  diagnostics.get_cross_file_diagnostics("", ["api"])
  |> should.equal([])
}

pub fn cross_file_multiple_blocks_mixed_test() {
  let source =
    "Expectations measured by \"known_bp\"\n  * \"item1\":\n    Provides { a: true }\n\nExpectations measured by \"unknown_bp\"\n  * \"item2\":\n    Provides { b: false }\n"
  let diags = diagnostics.get_cross_file_diagnostics(source, ["known_bp"])
  case diags {
    [diag] -> {
      diag.message
      |> should.equal("Measurement 'unknown_bp' not found in workspace")
    }
    _ -> should.fail()
  }
}

pub fn cross_file_empty_known_list_reports_all_test() {
  let source =
    "Expectations measured by \"my_measurement\"\n  * \"item\":\n    Provides { status: true }\n"
  let diags = diagnostics.get_cross_file_diagnostics(source, [])
  case diags {
    [diag] -> {
      diag.message
      |> should.equal("Measurement 'my_measurement' not found in workspace")
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
    "Expectations measured by \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"org.team.svc.dep\"] } }\n"
  diagnostics.get_cross_file_dependency_diagnostics(source, [
    "org.team.svc.dep",
  ])
  |> should.equal([])
}

pub fn dependency_unknown_target_returns_diagnostic_test() {
  let source =
    "Expectations measured by \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"org.team.svc.dep\"] } }\n"
  let diags = diagnostics.get_cross_file_dependency_diagnostics(source, [])
  case diags {
    [diag] -> {
      diag.severity |> should.equal(lsp_types.DsError)
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
    "Expectations measured by \"bp\"\n  * \"item\":\n    Provides { status: true }\n"
  diagnostics.get_cross_file_dependency_diagnostics(source, [])
  |> should.equal([])
}

pub fn dependency_multiple_mixed_test() {
  let source =
    "Expectations measured by \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"known.t.s.dep\", \"unknown.t.s.dep\"] } }\n"
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
    "Expectations measured by \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"org.t.s.dep\"], soft: [\"org.t.s.dep\"] } }\n"
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
// * ✅ valid expects with known measurement returns no diagnostics
// * ✅ valid expects with unknown measurement returns MeasurementNotFound
// * ✅ expects with unknown dependency returns DependencyNotFound
// * ✅ combines validation + cross-file + dependency diagnostics
// * ✅ invalid syntax returns parse error only

pub fn all_diagnostics_empty_content_test() {
  diagnostics.get_all_diagnostics("", [], [])
  |> should.equal([])
}

pub fn all_diagnostics_valid_expects_known_measurement_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  diagnostics.get_all_diagnostics(source, ["api_availability"], [])
  |> should.equal([])
}

pub fn all_diagnostics_unknown_measurement_test() {
  let source =
    "Expectations measured by \"api_availability\"\n  * \"checkout\":\n    Provides { status: true }\n"
  let diags = diagnostics.get_all_diagnostics(source, [], [])
  let has_bp_not_found =
    list.any(diags, fn(d) {
      d.code == diagnostics.MeasurementNotFound
      && string.contains(d.message, "api_availability")
    })
  has_bp_not_found |> should.be_true()
}

pub fn all_diagnostics_unknown_dependency_test() {
  let source =
    "Expectations measured by \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"org.team.svc.dep\"] } }\n"
  let diags = diagnostics.get_all_diagnostics(source, ["bp"], [])
  let has_dep_not_found =
    list.any(diags, fn(d) {
      d.code == diagnostics.DependencyNotFound
      && string.contains(d.message, "org.team.svc.dep")
    })
  has_dep_not_found |> should.be_true()
}

pub fn all_diagnostics_combines_all_checks_test() {
  // Expects file with validation error (undefined extendable), unknown measurement, and unknown dep
  let source =
    "Expectations measured by \"unknown_bp\"\n  * \"item\" extends [_nonexistent]:\n    Provides { env: \"staging\", relations: { hard: [\"org.t.s.dep\"] } }\n"
  let diags = diagnostics.get_all_diagnostics(source, [], [])
  // Should have validation error (undefined extendable), measurement not found, and dependency not found
  let has_undefined =
    list.any(diags, fn(d) { string.contains(d.message, "Undefined extendable") })
  let has_bp =
    list.any(diags, fn(d) { d.code == diagnostics.MeasurementNotFound })
  let has_dep =
    list.any(diags, fn(d) { d.code == diagnostics.DependencyNotFound })
  has_undefined |> should.be_true()
  has_bp |> should.be_true()
  has_dep |> should.be_true()
}

pub fn all_diagnostics_parse_error_test() {
  let source = "\"test\":\n  Requires { env: Unknown }"
  let diags = diagnostics.get_all_diagnostics(source, [], [])
  // Should produce at least one diagnostic (parse error)
  case diags {
    [first, ..] -> {
      first.severity |> should.equal(lsp_types.DsError)
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
// * measurements file returns type aliases, extendables, and items (no fields)
// * expects file returns extendables and items (no fields)
// * invalid source returns empty list

pub fn workspace_symbols_empty_test() {
  workspace_symbols.get_workspace_symbols("")
  |> should.equal([])
}

pub fn workspace_symbols_measurements_test() {
  let source =
    "_env (Type): String { x | x in { \"prod\", \"staging\" } }
_base (Requires): { env: String }

\"api\":
  Requires { threshold: Float }
  Provides { value: \"x\" }
"
  let symbols = workspace_symbols.get_workspace_symbols(source)
  let names = list.map(symbols, fn(s) { s.name })
  // Should include the type alias, extendable, and measurement item
  list.contains(names, "_env") |> should.be_true()
  list.contains(names, "_base") |> should.be_true()
  list.contains(names, "api") |> should.be_true()
  // Should have exactly 3 symbols (no fields like env, threshold, value)
  list.length(symbols) |> should.equal(3)
}

pub fn workspace_symbols_expects_test() {
  let source =
    "Expectations measured by \"api_availability\"
  * \"checkout\":
    Provides { status: true }
  * \"payments\":
    Provides { status: true }
"
  let symbols = workspace_symbols.get_workspace_symbols(source)
  let names = list.map(symbols, fn(s) { s.name })
  // Should include expect items
  list.contains(names, "checkout") |> should.be_true()
  list.contains(names, "payments") |> should.be_true()
  // Should have exactly 2 symbols (no fields like status)
  list.length(symbols) |> should.equal(2)
}

pub fn workspace_symbols_no_fields_test() {
  let source =
    "\"api\":
  Requires { env: String, threshold: Float }
  Provides { value: \"x\" }
"
  let symbols = workspace_symbols.get_workspace_symbols(source)
  let names = list.map(symbols, fn(s) { s.name })
  // Only the measurement item, not fields
  names |> should.equal(["api"])
}

pub fn workspace_symbols_invalid_source_test() {
  workspace_symbols.get_workspace_symbols("totally invalid {{{ source")
  |> should.equal([])
}

pub fn workspace_symbols_kind_values_test() {
  let source =
    "_env (Type): String { x | x in { \"prod\" } }
_base (Provides): {}

\"api\":
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
// * measurement item name returns MeasurementKind item
// * expect item name returns ExpectationKind item with measurement
// * keyword returns empty list
// * empty space returns empty list
// * field name returns empty list

pub fn type_hierarchy_measurement_item_test() {
  let source =
    "\"api\":
  Requires { env: String }
  Provides { value: \"x\" }
"
  let items = type_hierarchy.prepare_type_hierarchy(source, 0, 3)
  case items {
    [item] -> {
      item.name |> should.equal("api")
      item.kind |> should.equal(MeasurementKind)
      item.measurement |> should.equal("")
      item.name_len |> should.equal(3)
    }
    _ -> should.fail()
  }
}

pub fn type_hierarchy_expect_item_test() {
  let source =
    "Expectations measured by \"api_availability\"
  * \"checkout\":
    Provides { status: true }
"
  let items = type_hierarchy.prepare_type_hierarchy(source, 1, 7)
  case items {
    [item] -> {
      item.name |> should.equal("checkout")
      item.kind |> should.equal(ExpectationKind)
      item.measurement |> should.equal("api_availability")
      item.name_len |> should.equal(8)
    }
    _ -> should.fail()
  }
}

pub fn type_hierarchy_keyword_returns_empty_test() {
  let source =
    "\"api\":
  Requires { env: String }
  Provides { value: \"x\" }
"
  type_hierarchy.prepare_type_hierarchy(source, 1, 4)
  |> should.equal([])
}

pub fn type_hierarchy_empty_space_returns_empty_test() {
  let source =
    "\"api\":
  Requires { env: String }
  Provides { value: \"x\" }
"
  type_hierarchy.prepare_type_hierarchy(source, 0, 5)
  |> should.equal([])
}

pub fn type_hierarchy_field_name_returns_empty_test() {
  let source =
    "\"api\":
  Requires { env: String }
  Provides { value: \"x\" }
"
  // "env" is a field name, not an item name
  type_hierarchy.prepare_type_hierarchy(source, 1, 14)
  |> should.equal([])
}

pub fn type_hierarchy_multiple_expects_blocks_test() {
  let source =
    "Expectations measured by \"bp_one\"\n  * \"item_a\":\n    Provides { status: true }\n\nExpectations measured by \"bp_two\"\n  * \"item_b\":\n    Provides { active: false }\n"
  let items = type_hierarchy.prepare_type_hierarchy(source, 5, 7)
  case items {
    [item] -> {
      item.name |> should.equal("item_b")
      item.measurement |> should.equal("bp_two")
    }
    _ -> should.fail()
  }
}

// ==========================================================================
// Cross-file measurement completion tests
// ==========================================================================

// ==== measurement header completion ====
// * suggests workspace measurement names when cursor is after Expectations measured by "
// * filters suggestions by partial prefix
// * returns empty when no workspace names provided
// * does not trigger after closing quote

pub fn measurement_header_completion_suggests_names_test() {
  let source = "Expectations measured by \""
  // Cursor right after the opening quote (line 0, col 26)
  let items =
    completion.get_completions(
      source,
      0,
      26,
      ["api_availability", "latency_slo"],
      [],
    )
  let labels = list.map(items, fn(i) { i.label })
  list.contains(labels, "api_availability") |> should.be_true()
  list.contains(labels, "latency_slo") |> should.be_true()
}

pub fn measurement_header_completion_filters_by_prefix_test() {
  let source = "Expectations measured by \"api"
  // Cursor after "api" (line 0, col 29)
  let items =
    completion.get_completions(
      source,
      0,
      29,
      ["api_availability", "latency_slo"],
      [],
    )
  let labels = list.map(items, fn(i) { i.label })
  list.contains(labels, "api_availability") |> should.be_true()
  list.contains(labels, "latency_slo") |> should.be_false()
}

pub fn measurement_header_completion_empty_without_names_test() {
  let source = "Expectations measured by \""
  let items = completion.get_completions(source, 0, 26, [], [])
  items |> should.equal([])
}

pub fn measurement_header_completion_not_after_closing_quote_test() {
  let source = "Expectations measured by \"api_availability\""
  // Cursor after the closing quote — should NOT be in header context
  let items =
    completion.get_completions(source, 0, 44, ["api_availability", "other"], [])
  let labels = list.map(items, fn(i) { i.label })
  // Should fall through to general context, not measurement header
  list.contains(labels, "api_availability") |> should.be_false()
}

// ==== compile_validated_measurements ====
// * ✅ valid measurements file returns Ok
// * ✅ invalid content returns Error(Nil)
// * ✅ expects file returns Error(Nil)

pub fn compile_validated_measurements_valid_test() {
  let source =
    "\"my_slo\":
  Requires { env: String }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\",
      threshold: 99.9%
    }
"
  case linker_diagnostics.compile_validated_measurements(source) {
    Ok(measurements) -> {
      { measurements != [] } |> should.be_true()
    }
    Error(_) -> should.fail()
  }
}

pub fn compile_validated_measurements_invalid_test() {
  linker_diagnostics.compile_validated_measurements("not valid caffeine")
  |> should.be_error()
}

pub fn compile_validated_measurements_expects_file_test() {
  // An expects-format file now parses as an empty measurements file via error
  // recovery (the measurements parser skips unrecognized tokens and finds no items).
  let source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides {
      env: \"prod\"
    }
"
  case linker_diagnostics.compile_validated_measurements(source) {
    Ok(measurements) -> {
      // Empty list — no measurement items found
      measurements |> should.equal([])
    }
    Error(_) -> should.fail()
  }
}

// ==== get_linker_diagnostics ====
// * ✅ all fields provided correctly returns empty
// * ✅ missing required field produces diagnostic
// * ✅ unknown field produces diagnostic
// * ✅ type mismatch produces diagnostic
// * ✅ optional/defaulted fields omitted returns no diagnostic
// * ✅ unknown measurement ref returns no diagnostic
// * ✅ empty measurements list returns no diagnostic

pub fn linker_diagnostics_all_correct_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\",
      threshold: 99.9%
    }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)

  let ex_source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides {
      env: \"prod\"
    }
"
  linker_diagnostics.get_linker_diagnostics(ex_source, measurements)
  |> should.equal([])
}

pub fn linker_diagnostics_missing_required_field_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String, status: Boolean }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\",
      threshold: 99.9%
    }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)

  // Missing 'env' and 'status' — both are required remaining params
  let ex_source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides {
    }
"
  let diags = linker_diagnostics.get_linker_diagnostics(ex_source, measurements)
  case diags {
    [diag] -> {
      diag.code |> should.equal(diagnostics.MissingRequiredFields)
      diag.severity |> should.equal(lsp_types.DsError)
      string.contains(diag.message, "env") |> should.be_true()
      string.contains(diag.message, "status") |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn linker_diagnostics_unknown_field_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\",
      threshold: 99.9%
    }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)

  let ex_source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides {
      env: \"prod\",
      xyz: \"unknown\"
    }
"
  let diags = linker_diagnostics.get_linker_diagnostics(ex_source, measurements)
  let unknown_diags =
    list.filter(diags, fn(d) { d.code == diagnostics.UnknownField })
  case unknown_diags {
    [diag] -> {
      string.contains(diag.message, "xyz") |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn linker_diagnostics_type_mismatch_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\"
  }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)

  // Providing an integer for 'threshold' which expects Percentage (float)
  let ex_source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides {
      env: \"prod\",
      threshold: 99
    }
"
  let diags = linker_diagnostics.get_linker_diagnostics(ex_source, measurements)
  let type_diags =
    list.filter(diags, fn(d) { d.code == diagnostics.TypeMismatch })
  case type_diags {
    [diag] -> {
      string.contains(diag.message, "threshold") |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn linker_diagnostics_optional_defaulted_omitted_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\",
      threshold: 99.9%
    }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)

  // Omitting optional fields (tags, runbook) and defaulted field (window_in_days) — no errors
  let ex_source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides {
      env: \"prod\"
    }
"
  linker_diagnostics.get_linker_diagnostics(ex_source, measurements)
  |> should.equal([])
}

pub fn linker_diagnostics_unknown_measurement_ref_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String }
  Provides {
    indicators: { good: \"q\", total: \"q\" },
    evaluation: \"good / total\",
      threshold: 99.9%
    }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)

  // Measurement ref "nonexistent" does not match — handled elsewhere, no linker diagnostic
  let ex_source =
    "Expectations measured by \"nonexistent\"
  * \"checkout\":
    Provides {
      env: \"prod\"
    }
"
  linker_diagnostics.get_linker_diagnostics(ex_source, measurements)
  |> should.equal([])
}

pub fn linker_diagnostics_empty_measurements_test() {
  let ex_source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides {
      env: \"prod\"
    }
"
  linker_diagnostics.get_linker_diagnostics(ex_source, [])
  |> should.equal([])
}

// ==========================================================================
// Measurement-aware field completion tests
// ==========================================================================

// ==== measurement-aware completion ====
// * ✅ suggests measurement remaining params in expects Provides
// * ✅ filters out already-filled fields
// * ✅ falls back to extendable-only with empty measurements

pub fn measurement_aware_completion_suggests_params_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String, status: Boolean }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\",
      threshold: 99.9%
    }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)

  let ex_source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides {
      env: \"prod\"

    }
"
  // Line 4 is the empty line inside Provides
  let items = completion.get_completions(ex_source, 4, 6, [], measurements)
  let labels = list.map(items, fn(i) { i.label })
  // status should be suggested (remaining param from measurement Requires)
  list.contains(labels, "status") |> should.be_true()
  // env is already provided, should NOT be suggested
  list.contains(labels, "env") |> should.be_false()
}

pub fn measurement_aware_completion_no_measurements_test() {
  let source =
    "_defaults (Provides): { env: \"production\" }

\"checkout\" extends [_defaults]:
  Requires {}
  Provides {
    status: true

  }
"
  // With empty measurements list, should get extendable fields from _defaults
  let items = completion.get_completions(source, 6, 6, [], [])
  let labels = list.map(items, fn(i) { i.label })
  list.contains(labels, "env") |> should.be_true()
}

pub fn measurement_aware_completion_unknown_measurement_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\",
      threshold: 99.9%
    }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)

  // This expects file references "nonexistent" which doesn't match any measurement
  // No measurement params should appear, falls through to general context
  let ex_source =
    "Expectations measured by \"nonexistent\"
  * \"checkout\":
    Provides {
      env: \"prod\"

    }
"
  let items = completion.get_completions(ex_source, 4, 6, [], measurements)
  let labels = list.map(items, fn(i) { i.label })
  // Should NOT contain measurement-specific params like "env"
  // (falls through to general completions since no field context found)
  let has_measurements_keyword = list.any(labels, fn(l) { l == "Measurements" })
  has_measurements_keyword |> should.be_true()
}

// ==========================================================================
// Signature help tests
// ==========================================================================

// ==== get_signature_help ====
// * ✅ returns SignatureHelp inside expects Provides block
// * ✅ active parameter matches current field line
// * ✅ returns None outside Provides block
// * ✅ returns None for measurements file

pub fn signature_help_in_provides_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String, status: Boolean }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\",
      threshold: 99.9%
    }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)

  let ex_source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides {
      env: \"prod\"
      status: true
    }
"
  // Cursor on the env field line (line 3)
  case signature_help.get_signature_help(ex_source, 3, 10, measurements) {
    option.Some(sig) -> {
      // Label should contain the measurement name and typed params
      { string.contains(sig.label, "my_slo") } |> should.be_true()
      // Should have parameters listed
      { sig.parameters != [] } |> should.be_true()
    }
    option.None -> should.fail()
  }
}

pub fn signature_help_active_parameter_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String, status: Boolean }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\",
      threshold: 99.9%
    }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)

  let ex_source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides {
      env: \"prod\"
      status: true
    }
"
  // Cursor on the status line (line 4)
  case signature_help.get_signature_help(ex_source, 4, 10, measurements) {
    option.Some(sig) -> {
      // Active parameter should be >= 0 (matched to status)
      { sig.active_parameter >= 0 } |> should.be_true()
    }
    option.None -> should.fail()
  }
}

pub fn signature_help_none_for_measurements_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String }
  Provides { value: \"test\" }
"
  signature_help.get_signature_help(bp_source, 2, 10, [])
  |> should.equal(option.None)
}

pub fn signature_help_none_outside_item_test() {
  let ex_source =
    "Expectations measured by \"my_slo\"
"
  signature_help.get_signature_help(ex_source, 0, 5, [])
  |> should.equal(option.None)
}

// ==========================================================================
// Inlay hints tests
// ==========================================================================

// ==== get_inlay_hints ====
// * ✅ returns type hints for fields matching measurement params
// * ✅ returns empty for fields not in measurement params
// * ✅ returns empty for measurements file
// * ✅ respects line range

pub fn inlay_hints_shows_types_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\",
      threshold: 99.9%
    }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)

  let ex_source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides {
      env: \"prod\"
    }
"
  let hints = inlay_hints.get_inlay_hints(ex_source, 0, 10, measurements)
  // Should have at least one hint for the "env" field
  { hints != [] } |> should.be_true()
  // Check that one of the hints contains a type string
  let labels = list.map(hints, fn(h) { h.label })
  let has_type_hint = list.any(labels, fn(l) { string.contains(l, "String") })
  has_type_hint |> should.be_true()
}

pub fn inlay_hints_empty_for_measurements_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String }
  Provides { value: \"test\" }
"
  inlay_hints.get_inlay_hints(bp_source, 0, 10, [])
  |> should.equal([])
}

pub fn inlay_hints_no_match_no_hints_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\",
      threshold: 99.9%
    }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)

  // Measurement ref "nonexistent" doesn't match
  let ex_source =
    "Expectations measured by \"nonexistent\"
  * \"checkout\":
    Provides {
      env: \"prod\"
    }
"
  inlay_hints.get_inlay_hints(ex_source, 0, 10, measurements)
  |> should.equal([])
}

pub fn inlay_hints_respects_range_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String, status: Boolean }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\",
      threshold: 99.9%
    }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)

  let ex_source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides {
      env: \"prod\"
      status: true
    }
"
  // Only request hints for line 0 (header line) — should get no field hints
  let hints = inlay_hints.get_inlay_hints(ex_source, 0, 0, measurements)
  hints |> should.equal([])
}

pub fn inlay_hints_duplicate_field_names_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\",
      threshold: 99.9%
    }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)

  // Two items both have an "env" field — hints should point to correct lines
  let ex_source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides {
      env: \"prod\"
    }
  * \"payments\":
    Provides {
      env: \"staging\"
    }
"
  let hints = inlay_hints.get_inlay_hints(ex_source, 0, 20, measurements)
  // Should have exactly 2 hints (one per item's env field)
  list.length(hints) |> should.equal(2)
  // First hint on line 3, second on line 7 — different lines
  let lines = list.map(hints, fn(h) { h.line })
  case lines {
    [first, second] -> {
      first |> should.equal(3)
      second |> should.equal(7)
    }
    _ -> should.fail()
  }
}

// ==========================================================================
// Feature (2): Richer type mismatch messages
// ==========================================================================
// * ✅ includes actual type in message

pub fn linker_diagnostics_type_mismatch_includes_actual_type_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\"
  }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)
  let ex_source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides {
      env: 42
    }
"
  let diags = linker_diagnostics.get_linker_diagnostics(ex_source, measurements)
  let type_diags =
    list.filter(diags, fn(d) { d.code == diagnostics.TypeMismatch })
  case type_diags {
    [diag] -> {
      string.contains(diag.message, "Expected String") |> should.be_true()
      string.contains(diag.message, "but got Int") |> should.be_true()
    }
    _ -> should.fail()
  }
}

// ==========================================================================
// Feature (6): Inlay hints show default values
// ==========================================================================
// * ✅ shows default suffix for Defaulted types

pub fn inlay_hints_shows_default_values_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: Defaulted(String, \"production\") }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\",
      threshold: 99.9%
    }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)
  let ex_source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides {
      env: \"prod\"
    }
"
  let hints = inlay_hints.get_inlay_hints(ex_source, 0, 10, measurements)
  let labels = list.map(hints, fn(h) { h.label })
  let has_default = list.any(labels, fn(l) { string.contains(l, "= ") })
  has_default |> should.be_true()
}

// ==========================================================================
// Feature (8): Hover resolves alias chains
// ==========================================================================
// * ✅ shows fully resolved type for chained aliases

pub fn hover_type_alias_chain_resolution_test() {
  let source =
    "_env (Type): String { x | x in { \"prod\", \"staging\" } }
_my_env (Type): _env

\"api\":
  Requires { env: _my_env }
  Provides { value: \"x\" }
"
  case hover.get_hover(source, 1, 1, []) {
    option.Some(markdown) -> {
      string.contains(markdown, "_my_env") |> should.be_true()
      string.contains(markdown, "Type alias") |> should.be_true()
      // Should show the full chain resolution
      string.contains(markdown, "_env") |> should.be_true()
      string.contains(markdown, "String") |> should.be_true()
    }
    option.None -> should.fail()
  }
}

// ==========================================================================
// Feature (7): Unused extendable/type alias warnings
// ==========================================================================
// * ✅ warns on unused extendable
// * ✅ warns on unused type alias
// * ✅ no warning when extendable is used
// * ✅ no warning when type alias is used
// * ✅ warns on unused extendable in expects file starting with extendable
// * ✅ no warning when extendable used in expects file starting with extendable
// * ✅ no warning when extendable used in unmeasured expects file

pub fn unused_extendable_warning_test() {
  let source =
    "_unused (Provides): {}

\"api\":
  Requires { env: String }
  Provides { value: \"test\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(lsp_types.DsWarning)
      string.contains(diag.message, "_unused") |> should.be_true()
      string.contains(diag.message, "never used") |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn used_extendable_no_warning_test() {
  let source =
    "_defaults (Provides): {}

\"api\" extends [_defaults]:
  Requires { env: String }
  Provides { value: \"test\" }
"
  diagnostics.get_diagnostics(source)
  |> should.equal([])
}

pub fn unused_type_alias_warning_test() {
  let source =
    "_env (Type): String
_unused (Type): Integer

\"api\":
  Requires { env: _env }
  Provides { value: \"test\" }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(lsp_types.DsWarning)
      string.contains(diag.message, "_unused") |> should.be_true()
      string.contains(diag.message, "never used") |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn used_type_alias_no_warning_test() {
  let source =
    "_env (Type): String

\"api\":
  Requires { env: _env }
  Provides { value: \"test\" }
"
  diagnostics.get_diagnostics(source)
  |> should.equal([])
}

pub fn type_alias_used_in_extendable_no_warning_test() {
  let source =
    "_env (Type): String

_defaults (Requires): { environment: Defaulted(_env, \"production\") }

\"api\" extends [_defaults]:
  Requires { }
  Provides { value: \"test\" }
"
  diagnostics.get_diagnostics(source)
  |> list.filter(fn(d) { d.code == diagnostics.UnusedTypeAlias })
  |> should.equal([])
}

pub fn unused_extendable_in_expects_file_warning_test() {
  let source =
    "_unused (Provides): { window_in_days: 30 }

Expectations measured by \"api_availability\"
  * \"checkout\":
    Provides { threshold: 99.9% }
"
  let diags = diagnostics.get_diagnostics(source)
  case diags {
    [diag] -> {
      diag.severity |> should.equal(lsp_types.DsWarning)
      string.contains(diag.message, "_unused") |> should.be_true()
      string.contains(diag.message, "never used") |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn used_extendable_in_expects_file_no_warning_test() {
  let source =
    "_defaults (Provides): { window_in_days: 30 }

Expectations measured by \"api_availability\"
  * \"checkout\" extends [_defaults]:
    Provides { threshold: 99.9% }
"
  diagnostics.get_diagnostics(source)
  |> should.equal([])
}

pub fn used_extendable_in_unmeasured_expects_no_warning_test() {
  let source =
    "_defaults (Provides): { window_in_days: 30 }

Unmeasured Expectations
  * \"checkout\" extends [_defaults]:
    Provides { threshold: 99.9% }
"
  diagnostics.get_diagnostics(source)
  |> should.equal([])
}

// ==========================================================================
// Feature (3): Hover shows measurement requires on expectation items
// ==========================================================================
// * ✅ shows requires fields when validated measurements available

pub fn hover_expect_item_shows_measurement_requires_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\",
      threshold: 99.9%
    }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)
  let source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides { env: \"prod\" }
"
  case hover.get_hover(source, 1, 7, measurements) {
    option.Some(markdown) -> {
      string.contains(markdown, "checkout") |> should.be_true()
      string.contains(markdown, "Measurement Requires") |> should.be_true()
      string.contains(markdown, "env") |> should.be_true()
      string.contains(markdown, "String") |> should.be_true()
    }
    option.None -> should.fail()
  }
}

// ==========================================================================
// Feature (5): Snippet completion for field names
// ==========================================================================
// * ✅ field completions include insert_text with snippet

pub fn field_completion_snippet_test() {
  let bp_source =
    "\"my_slo\":
  Requires { env: String }
  Provides {
    indicators: { good: \"query_good\", total: \"query_total\" },
    evaluation: \"good / total\"
  }
"
  let assert Ok(measurements) =
    linker_diagnostics.compile_validated_measurements(bp_source)
  let source =
    "Expectations measured by \"my_slo\"
  * \"checkout\":
    Provides {

    }
"
  let items = completion.get_completions(source, 3, 6, [], measurements)
  let env_items = list.filter(items, fn(i) { i.label == "env" })
  case env_items {
    [item] -> {
      item.insert_text |> should.equal(option.Some("env: $1"))
      item.insert_text_format |> should.equal(option.Some(2))
    }
    _ -> should.fail()
  }
}

// ==========================================================================
// Feature (11): Dead measurement detection
// ==========================================================================
// * ✅ detects unreferenced measurements
// * ✅ no warning when measurement has expectations

pub fn dead_measurement_detected_test() {
  let source =
    "\"api\":
  Requires { env: String }
  Provides { indicators: { good: \"q\", total: \"t\" }, evaluation: \"good / total\" }
"
  let diags = diagnostics.get_dead_measurement_diagnostics(source, [])
  case diags {
    [diag] -> {
      diag.severity |> should.equal(lsp_types.DsWarning)
      string.contains(diag.message, "api") |> should.be_true()
      string.contains(diag.message, "no expectations") |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn referenced_measurement_no_dead_warning_test() {
  let source =
    "\"api\":
  Requires { env: String }
  Provides { indicators: { good: \"q\", total: \"t\" }, evaluation: \"good / total\" }
"
  diagnostics.get_dead_measurement_diagnostics(source, ["api"])
  |> should.equal([])
}

// ==========================================================================
// LSP type converter functions
// ==========================================================================
// * ✅ completion_item_kind_to_int maps all 5 variants
// * ✅ symbol_kind_to_int maps all 5 variants
// * ✅ diagnostic_severity_to_int maps both variants

pub fn completion_item_kind_to_int_test() {
  lsp_types.completion_item_kind_to_int(lsp_types.CikField)
  |> should.equal(5)
  lsp_types.completion_item_kind_to_int(lsp_types.CikVariable)
  |> should.equal(6)
  lsp_types.completion_item_kind_to_int(lsp_types.CikClass)
  |> should.equal(7)
  lsp_types.completion_item_kind_to_int(lsp_types.CikModule)
  |> should.equal(9)
  lsp_types.completion_item_kind_to_int(lsp_types.CikKeyword)
  |> should.equal(14)
}

pub fn symbol_kind_to_int_test() {
  lsp_types.symbol_kind_to_int(lsp_types.SkModule)
  |> should.equal(2)
  lsp_types.symbol_kind_to_int(lsp_types.SkClass)
  |> should.equal(5)
  lsp_types.symbol_kind_to_int(lsp_types.SkProperty)
  |> should.equal(7)
  lsp_types.symbol_kind_to_int(lsp_types.SkVariable)
  |> should.equal(13)
  lsp_types.symbol_kind_to_int(lsp_types.SkTypeParameter)
  |> should.equal(26)
}

pub fn diagnostic_severity_to_int_test() {
  lsp_types.diagnostic_severity_to_int(lsp_types.DsError)
  |> should.equal(1)
  lsp_types.diagnostic_severity_to_int(lsp_types.DsWarning)
  |> should.equal(2)
}

// ==========================================================================
// Position utility functions
// ==========================================================================
// * ✅ find_all_quoted_string_positions finds target on single line
// * ✅ find_all_quoted_string_positions finds target on multiple lines
// * ✅ find_all_quoted_string_positions returns empty for no match
// * ✅ find_all_quoted_string_positions finds multiple occurrences on same line
// * ✅ find_defined_symbol_positions finds extendable symbol
// * ✅ find_defined_symbol_positions finds item name symbol
// * ✅ find_defined_symbol_positions returns empty for non-symbol

pub fn find_all_quoted_string_positions_single_test() {
  let content = "    Provides { name: \"hello\" }\n"
  position_utils.find_all_quoted_string_positions(content, "hello")
  |> should.equal([#(0, 22)])
}

pub fn find_all_quoted_string_positions_multiple_lines_test() {
  let content =
    "line 0\n\"target\" on line 1\nline 2\nand \"target\" on line 3\n"
  position_utils.find_all_quoted_string_positions(content, "target")
  |> should.equal([#(1, 1), #(3, 5)])
}

pub fn find_all_quoted_string_positions_no_match_test() {
  let content = "no quotes here\njust plain text\n"
  position_utils.find_all_quoted_string_positions(content, "missing")
  |> should.equal([])
}

pub fn find_all_quoted_string_positions_same_line_twice_test() {
  let content = "    hard: [\"a.b.c.d\", \"a.b.c.d\"]\n"
  let result =
    position_utils.find_all_quoted_string_positions(content, "a.b.c.d")
  // Both occurrences found (order may vary for same-line matches)
  list.length(result) |> should.equal(2)
  list.contains(result, #(0, 12)) |> should.be_true()
  list.contains(result, #(0, 23)) |> should.be_true()
}

pub fn find_defined_symbol_positions_extendable_test() {
  let content =
    "_defaults (Requires): { env: String }\n\n\"api\" extends [_defaults]:\n  Requires {}\n  Provides {}\n"
  // Cursor on '_defaults' at line 0, col 1
  let result = position_utils.find_defined_symbol_positions(content, 0, 1)
  // Should find occurrences at definition (line 0) and reference (line 3)
  { list.length(result) >= 2 } |> should.be_true()
}

pub fn find_defined_symbol_positions_item_name_test() {
  let content =
    "\"api_avail\":\n  Requires {}\n  Provides {}\n\nExpectations measured by \"api_avail\"\n  * \"my_slo\":\n    Provides {}\n"
  // Cursor on 'api_avail' at line 0, col 1 (inside quotes of the item name)
  let result = position_utils.find_defined_symbol_positions(content, 0, 1)
  // Should find the measurement item name and the expectations reference
  { list.length(result) >= 2 } |> should.be_true()
}

pub fn find_defined_symbol_positions_non_symbol_test() {
  let content = "\"api\":\n  Requires { env: String }\n"
  // Cursor on 'env' — not a defined symbol (not _name or * "name")
  position_utils.find_defined_symbol_positions(content, 2, 16)
  |> should.equal([])
}

// ==========================================================================
// Definition: relation ref with range
// ==========================================================================
// * ✅ get_relation_ref_with_range_at_position returns ref and start col
// * ✅ get_relation_ref_with_range_at_position returns None outside quotes
// * ✅ get_relation_ref_with_range_at_position returns None for non-dotted path

pub fn relation_ref_with_range_valid_test() {
  let source =
    "Expectations measured by \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"org.team.svc.dep\"] } }\n"
  // Line 2, cursor on 'o' of org.team.svc.dep
  case definition.get_relation_ref_with_range_at_position(source, 2, 36) {
    option.Some(#(ref, start_col)) -> {
      ref |> should.equal("org.team.svc.dep")
      // Start col should be the position of 'o' after the opening quote
      { start_col >= 35 && start_col <= 37 } |> should.be_true()
    }
    option.None -> should.fail()
  }
}

pub fn relation_ref_with_range_outside_quotes_test() {
  let source =
    "Expectations measured by \"bp\"\n  * \"item\":\n    Provides { relations: { hard: [\"org.team.svc.dep\"] } }\n"
  // Line 2, cursor on '[' — outside quotes
  definition.get_relation_ref_with_range_at_position(source, 2, 34)
  |> should.equal(option.None)
}

pub fn relation_ref_with_range_non_dotted_test() {
  let source =
    "Expectations measured by \"bp\"\n  * \"item\":\n    Provides { tags: [\"not_a_path\"] }\n"
  // Cursor inside "not_a_path" — not 4-segment dotted
  definition.get_relation_ref_with_range_at_position(source, 2, 23)
  |> should.equal(option.None)
}
