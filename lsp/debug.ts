// Debug logging for the LSP server.
// Gated on CAFFEINE_LSP_DEBUG env var; writes to stderr to avoid
// interfering with the stdio LSP transport.

import process from "node:process";

const enabled = !!process.env.CAFFEINE_LSP_DEBUG;

/** Log a debug message to stderr when CAFFEINE_LSP_DEBUG is set. */
export function debug(msg: string): void {
  if (enabled) {
    process.stderr.write(`[caffeine-lsp] ${msg}\n`);
  }
}
