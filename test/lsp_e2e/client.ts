/**
 * LSP test client for e2e testing the Caffeine language server.
 *
 * Spawns lsp_server.ts as a subprocess, communicates via JSON-RPC over stdio,
 * and provides convenience methods for all LSP operations.
 */

// deno-lint-ignore-file no-explicit-any

const CONTENT_LENGTH_HEADER = "Content-Length: ";
const HEADER_DELIMITER = "\r\n\r\n";

interface PendingRequest {
  resolve: (value: any) => void;
  reject: (reason: any) => void;
  method: string;
}

interface JsonRpcRequest {
  jsonrpc: "2.0";
  id: number;
  method: string;
  params?: any;
}

interface JsonRpcNotification {
  jsonrpc: "2.0";
  method: string;
  params?: any;
}

interface JsonRpcResponse {
  jsonrpc: "2.0";
  id: number;
  result?: any;
  error?: { code: number; message: string; data?: any };
}

export interface Diagnostic {
  range: Range;
  severity?: number;
  code?: string | number;
  source?: string;
  message: string;
}

export interface Range {
  start: Position;
  end: Position;
}

export interface Position {
  line: number;
  character: number;
}

export interface DiagnosticsNotification {
  uri: string;
  diagnostics: Diagnostic[];
}

export class LspTestClient {
  private process: Deno.ChildProcess | null = null;
  private nextId = 1;
  private pending = new Map<number, PendingRequest>();
  private notifications: { method: string; params: any }[] = [];
  private diagnosticWaiters: {
    uri: string;
    resolve: (params: DiagnosticsNotification | PromiseLike<DiagnosticsNotification>) => void;
    reject: (reason: any) => void;
  }[] = [];
  private readBuffer: Uint8Array = new Uint8Array(0);
  private readLoopPromise: Promise<void> | null = null;
  private writer: WritableStreamDefaultWriter<Uint8Array> | null = null;
  private closed = false;
  private rootDir: string;

  constructor(rootDir: string) {
    this.rootDir = rootDir;
  }

  /** Start the LSP server subprocess and begin reading responses. */
  async start(): Promise<void> {
    const command = new Deno.Command("deno", {
      args: [
        "run",
        "--no-check",
        "--allow-read",
        "--allow-write",
        "--allow-env",
        "lsp_server.ts",
      ],
      cwd: this.rootDir,
      stdin: "piped",
      stdout: "piped",
      stderr: "piped",
    });

    this.process = command.spawn();
    this.writer = this.process.stdin.getWriter();

    // Start the async read loop
    this.readLoopPromise = this.readLoop(this.process.stdout);

    // Drain stderr to prevent blocking
    this.drainStderr(this.process.stderr);
  }

  /** Full LSP initialize handshake. */
  async initialize(rootUri?: string): Promise<any> {
    const result = await this.sendRequest("initialize", {
      processId: Deno.pid,
      rootUri: rootUri ?? `file://${this.rootDir}`,
      capabilities: {
        textDocument: {
          synchronization: { dynamicRegistration: false },
          hover: { contentFormat: ["markdown", "plaintext"] },
          completion: {
            completionItem: { snippetSupport: false },
          },
          definition: {},
          formatting: {},
          semanticTokens: {
            tokenTypes: [],
            tokenModifiers: [],
            formats: ["relative"],
            requests: { full: true },
          },
          codeAction: {
            codeActionLiteralSupport: {
              codeActionKind: { valueSet: ["quickfix"] },
            },
          },
          documentSymbol: {},
          references: {},
          rename: { prepareSupport: true },
        },
        workspace: {},
      },
    });

    // Send initialized notification
    this.sendNotification("initialized", {});

    return result;
  }

  /** Open a text document. */
  openDocument(uri: string, text: string, version = 1): void {
    this.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri,
        languageId: "caffeine",
        version,
        text,
      },
    });
  }

  /** Send a full-content change for a document. */
  changeDocument(uri: string, text: string, version: number): void {
    this.sendNotification("textDocument/didChange", {
      textDocument: { uri, version },
      contentChanges: [{ text }],
    });
  }

  /** Close a text document. */
  closeDocument(uri: string): void {
    this.sendNotification("textDocument/didClose", {
      textDocument: { uri },
    });
  }

  /** Send textDocument/hover request. */
  async hover(
    uri: string,
    line: number,
    character: number,
  ): Promise<any | null> {
    return await this.sendRequest("textDocument/hover", {
      textDocument: { uri },
      position: { line, character },
    });
  }

  /** Send textDocument/completion request. */
  async completion(
    uri: string,
    line: number,
    character: number,
  ): Promise<any[]> {
    return await this.sendRequest("textDocument/completion", {
      textDocument: { uri },
      position: { line, character },
    });
  }

  /** Send textDocument/definition request. */
  async definition(
    uri: string,
    line: number,
    character: number,
  ): Promise<any | null> {
    return await this.sendRequest("textDocument/definition", {
      textDocument: { uri },
      position: { line, character },
    });
  }

  /** Send textDocument/formatting request. */
  async formatting(uri: string): Promise<any[]> {
    return await this.sendRequest("textDocument/formatting", {
      textDocument: { uri },
      options: { tabSize: 2, insertSpaces: true },
    });
  }

  /** Send textDocument/semanticTokens/full request. */
  async semanticTokens(uri: string): Promise<any> {
    return await this.sendRequest("textDocument/semanticTokens/full", {
      textDocument: { uri },
    });
  }

  /** Send textDocument/documentSymbol request. */
  async documentSymbols(uri: string): Promise<any[]> {
    return await this.sendRequest("textDocument/documentSymbol", {
      textDocument: { uri },
    });
  }

  /** Send textDocument/codeAction request. */
  async codeActions(
    uri: string,
    range: Range,
    diagnostics: Diagnostic[],
  ): Promise<any[]> {
    return await this.sendRequest("textDocument/codeAction", {
      textDocument: { uri },
      range,
      context: { diagnostics },
    });
  }

  /** Send textDocument/references request. */
  async references(
    uri: string,
    line: number,
    character: number,
  ): Promise<any[]> {
    return await this.sendRequest("textDocument/references", {
      textDocument: { uri },
      position: { line, character },
      context: { includeDeclaration: true },
    });
  }

  /** Send textDocument/rename request. */
  async rename(
    uri: string,
    line: number,
    character: number,
    newName: string,
  ): Promise<any | null> {
    return await this.sendRequest("textDocument/rename", {
      textDocument: { uri },
      position: { line, character },
      newName,
    });
  }

  /**
   * Wait for a textDocument/publishDiagnostics notification for the given URI.
   * Returns the diagnostics params once received, or rejects on timeout.
   */
  waitForDiagnostics(
    uri: string,
    timeoutMs = 5000,
  ): Promise<DiagnosticsNotification> {
    // Check existing notifications first
    const idx = this.notifications.findIndex(
      (n) =>
        n.method === "textDocument/publishDiagnostics" && n.params.uri === uri,
    );
    if (idx !== -1) {
      const match = this.notifications[idx];
      this.notifications.splice(idx, 1);
      return Promise.resolve(match.params);
    }

    // Otherwise wait for one
    return new Promise<DiagnosticsNotification>((resolve, reject) => {
      const waiter = { uri, resolve, reject };
      this.diagnosticWaiters.push(waiter);

      const timer = setTimeout(() => {
        const i = this.diagnosticWaiters.indexOf(waiter);
        if (i !== -1) this.diagnosticWaiters.splice(i, 1);
        reject(
          new Error(
            `Timed out waiting for diagnostics on ${uri} after ${timeoutMs}ms`,
          ),
        );
      }, timeoutMs);

      // Replace resolve to also clear the timer
      const originalResolve = waiter.resolve;
      waiter.resolve = (params) => {
        clearTimeout(timer);
        originalResolve(params);
      };
    });
  }

  /** Clear all collected notifications. */
  clearNotifications(): void {
    this.notifications = [];
  }

  /** Send shutdown request and exit notification, then kill the process. */
  async shutdown(): Promise<void> {
    if (this.closed) return;
    this.closed = true;

    try {
      await this.sendRequest("shutdown", null);
      this.sendNotification("exit", null);
    } catch {
      // Server may have already exited
    }

    // Give it a moment then force kill
    await delay(100);

    try {
      this.writer?.close().catch(() => {});
    } catch {
      // Ignore
    }

    try {
      this.process?.kill("SIGTERM");
    } catch {
      // Process may have already exited
    }

    // Wait for the read loop to finish
    try {
      await this.readLoopPromise;
    } catch {
      // Ignore
    }
  }

  // --- Internal methods ---

  private async sendRequest(method: string, params: any): Promise<any> {
    const id = this.nextId++;
    const message: JsonRpcRequest = {
      jsonrpc: "2.0",
      id,
      method,
      params,
    };

    const promise = new Promise<any>((resolve, reject) => {
      this.pending.set(id, { resolve, reject, method });
    });

    await this.writeMessage(message);

    // Add timeout
    const timeoutMs = 10000;
    const timeout = new Promise<never>((_, reject) => {
      setTimeout(
        () => reject(new Error(`Request ${method} (id=${id}) timed out`)),
        timeoutMs,
      );
    });

    return Promise.race([promise, timeout]);
  }

  private sendNotification(method: string, params: any): void {
    const message: JsonRpcNotification = {
      jsonrpc: "2.0",
      method,
      params,
    };

    this.writeMessage(message).catch(() => {
      // Ignore write errors on notifications
    });
  }

  private async writeMessage(message: any): Promise<void> {
    const body = JSON.stringify(message);
    const encoded = new TextEncoder().encode(body);
    const header = new TextEncoder().encode(
      `${CONTENT_LENGTH_HEADER}${encoded.length}${HEADER_DELIMITER}`,
    );

    const combined = new Uint8Array(header.length + encoded.length);
    combined.set(header);
    combined.set(encoded, header.length);

    await this.writer?.write(combined);
  }

  private async readLoop(stdout: ReadableStream<Uint8Array>): Promise<void> {
    const reader = stdout.getReader();

    try {
      while (!this.closed) {
        // Read until we have a complete header
        let headerEnd = -1;
        while (headerEnd === -1) {
          const { value, done } = await reader.read();
          if (done) return;
          if (value) {
            this.readBuffer = concat(this.readBuffer, new Uint8Array(value));
          }
          headerEnd = findSequence(
            this.readBuffer,
            new TextEncoder().encode(HEADER_DELIMITER),
          );
        }

        // Parse header to get content length
        const headerStr = new TextDecoder().decode(
          this.readBuffer.slice(0, headerEnd),
        );
        const match = headerStr.match(/Content-Length:\s*(\d+)/i);
        if (!match) {
          throw new Error(`Invalid header: ${headerStr}`);
        }
        const contentLength = parseInt(match[1], 10);
        const bodyStart = headerEnd + HEADER_DELIMITER.length;

        // Read until we have the full body
        while (this.readBuffer.length < bodyStart + contentLength) {
          const { value, done } = await reader.read();
          if (done) return;
          if (value) {
            this.readBuffer = concat(this.readBuffer, new Uint8Array(value));
          }
        }

        // Extract and parse the body
        const bodyBytes = this.readBuffer.slice(
          bodyStart,
          bodyStart + contentLength,
        );
        this.readBuffer = this.readBuffer.slice(bodyStart + contentLength);
        const bodyStr = new TextDecoder().decode(bodyBytes);

        let msg: any;
        try {
          msg = JSON.parse(bodyStr);
        } catch {
          continue;
        }

        this.handleMessage(msg);
      }
    } catch {
      // Stream closed or error — reject all pending requests
      for (const [, pending] of this.pending) {
        pending.reject(new Error("LSP connection closed"));
      }
      this.pending.clear();
    } finally {
      reader.releaseLock();
    }
  }

  private handleMessage(msg: any): void {
    if ("id" in msg && ("result" in msg || "error" in msg)) {
      // Response
      const response = msg as JsonRpcResponse;
      const pending = this.pending.get(response.id);
      if (pending) {
        this.pending.delete(response.id);
        if (response.error) {
          pending.reject(
            new Error(
              `LSP error (${pending.method}): ${response.error.message}`,
            ),
          );
        } else {
          pending.resolve(response.result);
        }
      }
    } else if (!("id" in msg) && "method" in msg) {
      // Server notification
      const notification = msg as JsonRpcNotification;

      // Check for diagnostic waiters
      if (notification.method === "textDocument/publishDiagnostics") {
        const uri = notification.params?.uri;
        const waiterIdx = this.diagnosticWaiters.findIndex(
          (w) => w.uri === uri,
        );
        if (waiterIdx !== -1) {
          const waiter = this.diagnosticWaiters[waiterIdx];
          this.diagnosticWaiters.splice(waiterIdx, 1);
          waiter.resolve(notification.params);
          return;
        }
      }

      this.notifications.push({
        method: notification.method,
        params: notification.params,
      });
    }
  }

  private async drainStderr(stderr: ReadableStream<Uint8Array>): Promise<void> {
    const reader = stderr.getReader();
    try {
      while (true) {
        const { done } = await reader.read();
        if (done) break;
      }
    } catch {
      // Ignore
    } finally {
      reader.releaseLock();
    }
  }
}

/** Concatenate two Uint8Arrays. */
function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const result = new Uint8Array(a.length + b.length);
  result.set(a);
  result.set(b, a.length);
  return result;
}

/** Find the index of a byte sequence within a buffer. Returns -1 if not found. */
function findSequence(buffer: Uint8Array, sequence: Uint8Array): number {
  outer: for (let i = 0; i <= buffer.length - sequence.length; i++) {
    for (let j = 0; j < sequence.length; j++) {
      if (buffer[i + j] !== sequence[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/** Simple delay helper. */
function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Wraps an async test function with a hard timeout.
 * If the test hangs (server doesn't respond, deadlock, etc.), this
 * rejects after timeoutMs so CI doesn't stall.
 */
export function withTimeout(
  fn: () => Promise<void>,
  timeoutMs = 30_000,
): () => Promise<void> {
  return () =>
    Promise.race([
      fn(),
      new Promise<never>((_, reject) =>
        setTimeout(
          () => reject(new Error(`Test timed out after ${timeoutMs}ms`)),
          timeoutMs,
        )
      ),
    ]);
}
