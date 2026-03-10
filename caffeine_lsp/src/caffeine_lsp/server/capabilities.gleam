/// LSP server capabilities declaration.
import caffeine_lang/constants
import caffeine_lsp/semantic_tokens
import gleam/json
import gleam/list

/// Build the full initialize result with server capabilities.
pub fn initialize_result() -> json.Json {
  json.object([
    #("capabilities", server_capabilities()),
    #(
      "serverInfo",
      json.object([
        #("name", json.string("caffeine-lsp")),
        #("version", json.string(constants.version)),
      ]),
    ),
  ])
}

/// Build the server capabilities JSON object.
fn server_capabilities() -> json.Json {
  json.object([
    // Full document sync.
    #("textDocumentSync", json.int(1)),
    #("hoverProvider", json.bool(True)),
    #("definitionProvider", json.bool(True)),
    #("declarationProvider", json.bool(True)),
    #("documentHighlightProvider", json.bool(True)),
    #("referencesProvider", json.bool(True)),
    #("renameProvider", json.object([#("prepareProvider", json.bool(True))])),
    #("foldingRangeProvider", json.bool(True)),
    #("selectionRangeProvider", json.bool(True)),
    #("linkedEditingRangeProvider", json.bool(True)),
    #("documentFormattingProvider", json.bool(True)),
    #("documentSymbolProvider", json.bool(True)),
    #("workspaceSymbolProvider", json.bool(True)),
    #("typeHierarchyProvider", json.bool(True)),
    #(
      "completionProvider",
      json.object([
        #(
          "triggerCharacters",
          json.preprocessed_array([
            json.string(":"),
            json.string("["),
            json.string("{"),
            json.string(","),
            json.string("\""),
          ]),
        ),
      ]),
    ),
    #(
      "signatureHelpProvider",
      json.object([
        #("triggerCharacters", json.preprocessed_array([json.string(":")])),
        #("retriggerCharacters", json.preprocessed_array([json.string(",")])),
      ]),
    ),
    #("inlayHintProvider", json.bool(True)),
    #(
      "codeActionProvider",
      json.object([
        #("codeActionKinds", json.preprocessed_array([json.string("quickfix")])),
      ]),
    ),
    #(
      "semanticTokensProvider",
      json.object([
        #(
          "legend",
          json.object([
            #(
              "tokenTypes",
              json.preprocessed_array(list.map(
                semantic_tokens.token_types,
                json.string,
              )),
            ),
            #("tokenModifiers", json.preprocessed_array([])),
          ]),
        ),
        #("full", json.bool(True)),
      ]),
    ),
  ])
}
