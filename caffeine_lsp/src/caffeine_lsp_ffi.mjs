import { Ok, Error } from "./gleam.mjs";

export function init_io() {
  return undefined;
}

export function read_line() {
  try {
    const chunks = [];
    const buf = new Uint8Array(1);
    while (true) {
      const n = Deno.stdin.readSync(buf);
      if (n === null || n === 0) return new Error(undefined);
      if (buf[0] === 10) break; // \n
      chunks.push(buf[0]);
    }
    return new Ok(new TextDecoder().decode(new Uint8Array(chunks)));
  } catch (_e) {
    return new Error(undefined);
  }
}

export function read_bytes(n) {
  try {
    const buf = new Uint8Array(n);
    let offset = 0;
    while (offset < n) {
      const bytesRead = Deno.stdin.readSync(buf.subarray(offset));
      if (bytesRead === null || bytesRead === 0) return new Error(undefined);
      offset += bytesRead;
    }
    return new Ok(new TextDecoder().decode(buf));
  } catch (_e) {
    return new Error(undefined);
  }
}

export function write_stdout(data) {
  Deno.stdout.writeSync(new TextEncoder().encode(data));
  return undefined;
}

export function write_stderr(data) {
  Deno.stderr.writeSync(new TextEncoder().encode(data + "\n"));
  return undefined;
}
