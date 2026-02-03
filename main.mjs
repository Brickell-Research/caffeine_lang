// Entry point for Deno compilation
// Intercepts "lsp" arg to launch TypeScript LSP server,
// otherwise runs the Gleam-compiled CLI.

const args = typeof Deno !== "undefined" ? Deno.args : [];

if (args.includes("lsp")) {
  // Patch process.kill so signal-0 "is alive?" checks don't crash the LSP
  // server under Deno's compiled binary. The vscode-languageserver library
  // periodically calls process.kill(pid, 0) to verify the parent editor
  // process is still running; under Deno this throws spuriously, causing
  // the server to exit after ~3 seconds.
  const { default: proc } = await import("node:process");
  const _kill = proc.kill.bind(proc);
  proc.kill = function (pid, signal) {
    if (signal === 0) {
      try {
        return _kill(pid, signal);
      } catch {
        return true;
      }
    }
    return _kill(pid, signal);
  };

  await import("./lsp_server.ts");
} else {
  const { main } = await import(
    "./caffeine_cli/build/dev/javascript/caffeine_cli/caffeine_cli.mjs"
  );
  main();
}
