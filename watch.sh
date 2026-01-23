#!/bin/bash
# Watch for changes in caffeine_lang/ and caffeine_cli/ and run tests

echo "Watching caffeine_lang/ and caffeine_cli/ for changes..."
echo "Press Ctrl+C to stop"

# Run tests once at startup
cd caffeine_lang && gleam test "$@" && cd ../caffeine_cli && gleam test "$@" && cd ..

# Watch for changes in both packages
fswatch -o caffeine_lang/src/ caffeine_lang/test/ caffeine_cli/src/ caffeine_cli/test/ | while read num ; do
  clear
  echo "Changes detected, running tests..."
  echo "=================================="
  cd caffeine_lang && gleam test "$@" && cd ../caffeine_cli && gleam test "$@" && cd ..
done
