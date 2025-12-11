export function halt(code) {
  if (typeof process !== "undefined" && process.exit) {
    // Node.js / Deno
    process.exit(code);
  } else if (typeof Deno !== "undefined") {
    // Deno alternative
    Deno.exit(code);
  }
  // Browser or other environments - can't really exit
  return undefined;
}
