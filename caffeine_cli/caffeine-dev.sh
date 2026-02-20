#!/bin/bash
# Development wrapper for running the caffeine CLI from local source.
# Point your VS Code extension to this script:
#   Settings > caffeine.serverPath = ~/BrickellResearch/caffeine/caffeine_cli/caffeine-dev.sh"
cd "$(dirname "$0")" || exit 1
exec gleam run -- "$@"
