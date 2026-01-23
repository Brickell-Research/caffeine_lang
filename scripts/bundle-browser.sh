#!/bin/bash
# Bundle the Caffeine compiler for browser use
# Requires: deno (for esbuild via deno task)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"

echo "Building Caffeine for browser..."

# Ensure JavaScript build is up to date (build caffeine_lang for the pure compiler API)
cd "$PROJECT_DIR/caffeine_lang"
gleam build --target=javascript

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create shims for Node.js modules that simplifile imports but we don't actually use
# (browser.gleam bypasses all file I/O)
cat > "$OUTPUT_DIR/node-shims.mjs" << 'EOF'
// Shims for Node.js modules - these are imported by simplifile but not used in browser mode
// Our browser.gleam bypasses all file I/O

export const fs = {
  readFileSync: () => { throw new Error("File I/O not available in browser"); },
  writeFileSync: () => { throw new Error("File I/O not available in browser"); },
  readdirSync: () => { throw new Error("File I/O not available in browser"); },
  statSync: () => { throw new Error("File I/O not available in browser"); },
  mkdirSync: () => { throw new Error("File I/O not available in browser"); },
  existsSync: () => false,
  unlinkSync: () => { throw new Error("File I/O not available in browser"); },
  rmdirSync: () => { throw new Error("File I/O not available in browser"); },
  copyFileSync: () => { throw new Error("File I/O not available in browser"); },
  renameSync: () => { throw new Error("File I/O not available in browser"); },
};

export const path = {
  join: (...args) => args.join('/'),
  dirname: (p) => p.split('/').slice(0, -1).join('/'),
  basename: (p) => p.split('/').pop(),
  resolve: (...args) => args.join('/'),
  isAbsolute: (p) => p.startsWith('/'),
};

export const process = {
  cwd: () => '/',
  env: {},
};

export default { fs, path, process };
EOF

# Create a wrapper module that exports the compiler API
cat > "$OUTPUT_DIR/caffeine-entry.mjs" << 'EOF'
// Browser entry point for Caffeine compiler
export { compile_from_strings } from "../caffeine_lang/build/dev/javascript/caffeine_lang/caffeine_lang/core/compiler.mjs";
EOF

# Bundle with esbuild (using deno), with node shims
echo "Bundling with esbuild..."
cd "$PROJECT_DIR"
deno run -A npm:esbuild "$OUTPUT_DIR/caffeine-entry.mjs" \
  --bundle \
  --format=esm \
  --platform=browser \
  --outfile="$OUTPUT_DIR/caffeine-browser.js" \
  --alias:node:fs="$OUTPUT_DIR/node-shims.mjs" \
  --alias:node:path="$OUTPUT_DIR/node-shims.mjs" \
  --alias:node:process="$OUTPUT_DIR/node-shims.mjs" \
  --minify

# Clean up temp files
rm "$OUTPUT_DIR/caffeine-entry.mjs"
rm "$OUTPUT_DIR/node-shims.mjs"

echo ""
echo "Bundle created: $OUTPUT_DIR/caffeine-browser.js"
ls -lh "$OUTPUT_DIR/caffeine-browser.js"
echo ""
echo "Usage in browser:"
echo '  import { compile_from_strings } from "./caffeine-browser.js";'
echo '  const result = compile_from_strings(blueprintsJson, expectationsJson, "org/team/service.json");'
