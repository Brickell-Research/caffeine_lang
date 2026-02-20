// Barrel re-export of all Gleam-compiled modules used by the LSP server.
// Single point of change if Gleam build paths move.

export {
  get_all_diagnostics,
  diagnostic_code_to_string,
  QuotedFieldName,
  BlueprintNotFound,
  DependencyNotFound,
  NoDiagnosticCode,
} from "../caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/diagnostics.mjs";

export { get_hover } from "../caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/hover.mjs";

export { get_completions } from "../caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/completion.mjs";

export {
  get_semantic_tokens,
  token_types,
} from "../caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/semantic_tokens.mjs";

export { get_symbols } from "../caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/document_symbols.mjs";

export {
  get_definition,
  get_blueprint_ref_at_position,
  get_relation_ref_with_range_at_position,
} from "../caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/definition.mjs";

export {
  get_code_actions,
  ActionDiagnostic,
} from "../caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/code_actions.mjs";

export { format } from "../caffeine_lsp/build/dev/javascript/caffeine_lang/caffeine_lang/frontend/formatter.mjs";

export { get_highlights } from "../caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/highlight.mjs";

export {
  get_references,
  get_blueprint_name_at,
  find_references_to_name,
} from "../caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/references.mjs";

export {
  prepare_rename,
  get_rename_edits,
} from "../caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/rename.mjs";

export { get_folding_ranges } from "../caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/folding_range.mjs";

export { get_selection_range } from "../caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/selection_range.mjs";

export { get_linked_editing_ranges } from "../caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/linked_editing_range.mjs";

export { get_workspace_symbols } from "../caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/workspace_symbols.mjs";

export {
  prepare_type_hierarchy,
  BlueprintKind,
} from "../caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/type_hierarchy.mjs";

// Gleam runtime types
export { Ok, toList } from "../caffeine_lsp/build/dev/javascript/prelude.mjs";
export { Some } from "../caffeine_lsp/build/dev/javascript/gleam_stdlib/gleam/option.mjs";
