#!/bin/bash
# post-tool-use.sh — Instant feedback after file edits
# Runs on: PostToolUse (matcher: Edit|Write)
#
# Runs a lightweight lint check on the specific file that was just changed.
# Non-blocking: exit 0 always. Errors are reported as stdout for context.
#
# Hook input (JSON on stdin) includes the tool call details.
# We extract the file path and lint only that file.

PROJECT_DIR="$(pwd)"

# Only run checks if the project has TypeScript/Node tooling
if [[ ! -f "$PROJECT_DIR/package.json" ]]; then
  exit 0
fi

# ─── Extract the changed file path from hook input ────────────────────────────

# Read stdin (hook input JSON) — contains tool_input with file_path
INPUT=$(cat)

# Extract file_path from the JSON input
FILE_PATH=$(echo "$INPUT" | grep -oP '"file_path"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"file_path"\s*:\s*"//;s/"$//' || true)

# If we couldn't extract a file path, skip
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Only lint TypeScript/JavaScript files
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx) ;;
  *) exit 0 ;;
esac

# ─── ESLint check on the specific changed file ───────────────────────────────

if command -v npx > /dev/null 2>&1 && [[ -f "$FILE_PATH" ]]; then
  LINT_OUTPUT=$(npx eslint --quiet --format compact "$FILE_PATH" 2>&1 | head -15)
  LINT_EXIT=$?

  if [[ $LINT_EXIT -ne 0 ]] && [[ -n "$LINT_OUTPUT" ]]; then
    ERROR_COUNT=$(echo "$LINT_OUTPUT" | grep -cE "Error|error" || true)
    echo "<post-edit-feedback type=\"eslint\" file=\"$FILE_PATH\">"
    echo "ESLint: $ERROR_COUNT issue(s) in $(basename "$FILE_PATH")"
    echo "$LINT_OUTPUT"
    echo "</post-edit-feedback>"
  fi
fi

exit 0
