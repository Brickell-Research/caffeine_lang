// Entry point for Bun compilation
// Intercepts "lsp" arg to launch TypeScript LSP server,
// otherwise runs the Gleam-compiled CLI.

const args = process.argv.slice(2);

if (args.includes("lsp")) {
  await import("./lsp_server.ts");
} else {
  const { main } = await import(
    "./caffeine_cli/build/dev/javascript/caffeine_cli/caffeine_cli.mjs"
  );
  main();
}
