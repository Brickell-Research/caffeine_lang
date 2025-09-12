#!/bin/bash
# Watch for changes in src/ and test/ directories and run tests

echo "Watching for changes in src/ and test/ directories..."
echo "Press Ctrl+C to stop"

# Run tests once at startup
gleam test

# Watch for changes
fswatch -o src/ test/ | while read num ; do
  clear
  echo "Changes detected, running tests..."
  echo "================================"
  gleam test
done 