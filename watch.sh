#!/bin/bash
# Watch for changes and run tests for different packages

PACKAGE=${1:-main}

case $PACKAGE in
  "cql")
    echo "Watching CQL package (lib/cql/) for changes..."
    echo "Press Ctrl+C to stop"
    
    # Run CQL tests once at startup
    echo "🔍 Running CQL package tests (16 tests)..."
    cd lib/cql && gleam test && cd ../..
    
    # Watch for changes in CQL package
    fswatch -o lib/cql/src/ lib/cql/test/ | while read num ; do
      clear
      echo "CQL package changes detected, running CQL tests..."
      echo "================================================="
      echo "🔍 Running CQL package tests (16 tests)..."
      cd lib/cql && gleam test && cd ../..
    done
    ;;
    
  "glaml_extended")
    echo "Watching glaml_extended package (lib/glaml_extended/) for changes..."
    echo "Press Ctrl+C to stop"
    
    # Run glaml_extended tests once at startup
    echo "📦 Running glaml_extended package tests (7 tests)..."
    cd lib/glaml_extended && gleam test && cd ../..
    
    # Watch for changes in glaml_extended package
    fswatch -o lib/glaml_extended/src/ lib/glaml_extended/test/ | while read num ; do
      clear
      echo "glaml_extended package changes detected, running glaml_extended tests..."
      echo "======================================================================"
      echo "📦 Running glaml_extended package tests (7 tests)..."
      cd lib/glaml_extended && gleam test && cd ../..
    done
    ;;
    
  "all")
    echo "Watching all packages for changes..."
    echo "Press Ctrl+C to stop"
    
    # Run all tests once at startup
    echo "🧪 Running all tests..."
    echo ""
    echo "📦 Main project tests (60 tests):"
    gleam test --target erlang
    echo ""
    echo "🔍 CQL package tests (16 tests):"
    cd lib/cql && gleam test && cd ../..
    echo ""
    echo "📦 glaml_extended package tests (7 tests):"
    cd lib/glaml_extended && gleam test && cd ../..
    
    # Watch for changes in all packages
    fswatch -o src/ test/ lib/cql/src/ lib/cql/test/ lib/glaml_extended/src/ lib/glaml_extended/test/ | while read num ; do
      clear
      echo "Changes detected, running all tests..."
      echo "====================================="
      
      echo "📦 Main project tests (60 tests):"
      gleam test --target erlang
      echo ""
      echo "🔍 CQL package tests (16 tests):"
      cd lib/cql && gleam test && cd ../..
      echo ""
      echo "📦 glaml_extended package tests (7 tests):"
      cd lib/glaml_extended && gleam test && cd ../..
      
      echo ""
      echo "✅ All tests completed! (83 total tests)"
    done
    ;;
    
  "main"|*)
    echo "Watching main project (src/ and test/) for changes..."
    echo "Press Ctrl+C to stop"
    
    # Run tests once at startup
    gleam test
    
    # Watch for changes in main project
    fswatch -o src/ test/ | while read num ; do
      clear
      echo "Main project changes detected, running tests..."
      echo "=============================================="
      gleam test
    done
    ;;
esac 