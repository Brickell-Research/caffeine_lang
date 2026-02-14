# Session Context

## User Prompts

### Prompt 1

<teammate-message teammate_id="team-lead">
You are on team "lsp-e2e-tests". Your name is "researcher-frameworks". 

Your task (Task #2): Research LSP e2e testing frameworks and patterns.

The Caffeine project has an LSP server written in TypeScript (lsp_server.ts at the project root) that runs via Deno. It communicates over stdio using JSON-RPC (the standard LSP protocol). The project root is /Users/rdurst/.REDACTED

Research and recom...

### Prompt 2

<teammate-message teammate_id="researcher-frameworks" color="green">
{"type":"task_assignment","taskId":"2","subject":"Research LSP e2e testing frameworks and patterns","description":"Research how to write integration/end-to-end tests for LSP servers that can run in CI/CD:\n1. Look at how the LSP protocol works over stdio (JSON-RPC)\n2. Research testing approaches: spawning the LSP as a subprocess and sending JSON-RPC messages\n3. Consider what tools/languages to use — the project already has ...

