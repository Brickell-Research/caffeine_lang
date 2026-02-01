#!/bin/bash
# Watch for changes in caffeine_lang/, caffeine_cli/, and caffeine_lsp/ and run tests

echo "Watching caffeine_lang/, caffeine_cli/, and caffeine_lsp/ for changes..."
echo "Press Ctrl+C to stop"

# Run tests once at startup
(cd caffeine_lang && gleam test "$@")
(cd caffeine_lsp && gleam test "$@")
(cd caffeine_cli && gleam test "$@")

# Watch for changes in all packages
fswatch -o -l 2 --exclude '\.git' --exclude 'build/' caffeine_lang/src/ caffeine_lang/test/ caffeine_cli/src/ caffeine_cli/test/ caffeine_lsp/src/ caffeine_lsp/test/ | while read num ; do
  clear
  echo "Changes detected, running tests..."
  echo "=================================="
  (cd caffeine_lang && gleam test "$@")
  (cd caffeine_lsp && gleam test "$@")
  (cd caffeine_cli && gleam test "$@")
done
