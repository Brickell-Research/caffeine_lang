#!/bin/bash
# Bundle the Caffeine compiler for browser use
# Requires: bun (for esbuild via bunx)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
BUILD_DIR="$PROJECT_DIR/build/dev/javascript/caffeine_lang/caffeine_lang"

echo "Building Caffeine for browser..."

# Ensure JavaScript build is up to date
cd "$PROJECT_DIR" || exit 1
gleam build --target=javascript

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Bundle with esbuild
echo "Bundling with esbuild..."
bunx esbuild "$BUILD_DIR/compiler.mjs" \
  --bundle \
  --format=esm \
  --outfile="$OUTPUT_DIR/caffeine-browser.js" \
  --minify

echo ""
echo "Bundle created: $OUTPUT_DIR/caffeine-browser.js"
ls -lh "$OUTPUT_DIR/caffeine-browser.js"
echo ""
echo "Usage in browser:"
echo '  import { compile_from_strings } from "./caffeine-browser.js";'
echo '  const result = compile_from_strings(blueprintsJson, expectationsJson, "org/team/service.json");'
