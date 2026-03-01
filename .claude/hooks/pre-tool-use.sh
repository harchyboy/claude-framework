#!/bin/bash
# pre-tool-use.sh — Attention injection before file modifications
# Runs on: PreToolUse (matched to Write, Edit, Bash)
#
# Injects the top of PROGRESS.md into Claude's context before every file
# modification. This keeps the current goal and phase in the model's recent
# attention window, preventing goal drift over long sessions.
#
# Based on the "attention manipulation through recitation" principle from
# Manus AI's context engineering research.

PROJECT_DIR="$(pwd)"

if [[ -f "$PROJECT_DIR/PROGRESS.md" ]]; then
  echo "<attention-anchor source=\"PROGRESS.md\">"
  head -30 "$PROJECT_DIR/PROGRESS.md"
  echo "</attention-anchor>"
fi
