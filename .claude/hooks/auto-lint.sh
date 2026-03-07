#!/usr/bin/env bash
set -euo pipefail

# Auto-lint hook — PostToolUse (Edit)
# Detects file type and runs the appropriate formatter silently.
# Always exits 0 (formatting is auto-fix, never blocking).

FILE_PATH="${CLAUDE_FILE_PATH:-}"

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
  exit 0
fi

EXT="${FILE_PATH##*.}"

format_js_ts() {
  if command -v npx &>/dev/null && [[ -f "package.json" ]]; then
    npx --yes prettier --write "$FILE_PATH" &>/dev/null || true
  elif command -v prettier &>/dev/null; then
    prettier --write "$FILE_PATH" &>/dev/null || true
  fi
}

format_python() {
  if command -v ruff &>/dev/null; then
    ruff format "$FILE_PATH" &>/dev/null || true
  elif command -v black &>/dev/null; then
    black --quiet "$FILE_PATH" &>/dev/null || true
  fi
}

case "$EXT" in
  js|jsx|ts|tsx|css|scss|html|json|md|yaml|yml)
    format_js_ts
    ;;
  py)
    format_python
    ;;
  *)
    # Unsupported file type — skip silently
    ;;
esac

exit 0
