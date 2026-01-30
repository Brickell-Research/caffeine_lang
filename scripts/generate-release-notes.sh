#!/usr/bin/env bash
set -euo pipefail

# Generate categorized release notes from git log between two tags.
# Usage: ./scripts/generate-release-notes.sh <current-tag> <previous-tag>
# Example: ./scripts/generate-release-notes.sh v3.0.21 v3.0.17

if [ $# -lt 2 ]; then
  echo "Usage: $0 <current-tag> <previous-tag>" >&2
  exit 1
fi

CURRENT_TAG="$1"
PREVIOUS_TAG="$2"

# Strip leading 'v' for display version
VERSION="${CURRENT_TAG#v}"

# Collect commits between tags (excluding merge commits)
COMMITS=$(git log --oneline --no-merges "${PREVIOUS_TAG}..${CURRENT_TAG}" 2>/dev/null || true)

if [ -z "$COMMITS" ]; then
  echo "## What's New in Caffeine v${VERSION}"
  echo ""
  echo "No changes recorded."
  exit 0
fi

# Arrays for each category
FEATURES=()
FIXES=()
REFACTORS=()
DOCS=()
TESTS=()
CHORES=()
OTHER=()

# Strip conventional commit prefix: "feat: msg" -> "msg", "feat(scope): msg" -> "msg"
strip_prefix() {
  printf '%s\n' "$1" | sed -E 's/^[a-z]+(\([^)]*\))?:[[:space:]]*//'
}

while IFS= read -r line; do
  # Skip empty lines
  [ -z "$line" ] && continue

  # Remove the short hash prefix (first word)
  msg="${line#* }"

  # Skip version bump commits
  if printf '%s\n' "$msg" | grep -qiE '^[0-9]+\.[0-9]+\.[0-9]+ bump'; then
    continue
  fi
  if printf '%s\n' "$msg" | grep -qiE '^bump.*[0-9]+\.[0-9]+\.[0-9]+'; then
    continue
  fi
  if printf '%s\n' "$msg" | grep -qiE '^v?[0-9]+\.[0-9]+\.[0-9]+$'; then
    continue
  fi

  # Categorize by conventional commit prefix
  case "$msg" in
    feat:*|feat\(*)         FEATURES+=("$(strip_prefix "$msg")") ;;
    fix:*|fix\(*)           FIXES+=("$(strip_prefix "$msg")") ;;
    refactor:*|refactor\(*) REFACTORS+=("$(strip_prefix "$msg")") ;;
    docs:*|docs\(*)         DOCS+=("$(strip_prefix "$msg")") ;;
    test:*|test\(*|tests:*) TESTS+=("$(strip_prefix "$msg")") ;;
    chore:*|chore\(*)       CHORES+=("$(strip_prefix "$msg")") ;;
    *)                      OTHER+=("$msg") ;;
  esac
done <<< "$COMMITS"

# Output markdown
echo "## What's New in Caffeine v${VERSION}"
echo ""

print_section() {
  local title="$1"
  shift
  local items=("$@")
  if [ ${#items[@]} -gt 0 ]; then
    echo "### ${title}"
    for item in "${items[@]}"; do
      # Trim leading whitespace and capitalize first letter
      item="$(printf '%s' "$item" | sed 's/^[[:space:]]*//')"
      first="$(printf '%s' "$item" | cut -c1 | tr '[:lower:]' '[:upper:]')"
      rest="$(printf '%s' "$item" | cut -c2-)"
      item="${first}${rest}"
      echo "- ${item}"
    done
    echo ""
  fi
}

print_section "Features" "${FEATURES[@]+"${FEATURES[@]}"}"
print_section "Bug Fixes" "${FIXES[@]+"${FIXES[@]}"}"
print_section "Refactoring" "${REFACTORS[@]+"${REFACTORS[@]}"}"
print_section "Documentation" "${DOCS[@]+"${DOCS[@]}"}"
print_section "Tests" "${TESTS[@]+"${TESTS[@]}"}"
print_section "Maintenance" "${CHORES[@]+"${CHORES[@]}"}"
print_section "Other" "${OTHER[@]+"${OTHER[@]}"}"
