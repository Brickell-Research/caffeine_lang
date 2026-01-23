import caffeine_lsp/server

/// Starts the Caffeine LSP server.
/// Communicates via JSON-RPC over stdin/stdout.
pub fn start() -> Nil {
  server.run()
}
