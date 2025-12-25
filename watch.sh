#!/bin/bash
# Watch for changes in src/ and test/ and run tests

echo "Watching main project (src/ and test/) for changes..."
echo "Press Ctrl+C to stop"

# Run tests once at startup
gleam test "$@"

# Watch for changes in main project
fswatch -o src/ test/ | while read num ; do
  clear
  echo "Changes detected, running tests..."
  echo "=================================="
  gleam test "$@"
done