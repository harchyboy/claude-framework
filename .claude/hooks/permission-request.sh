#!/bin/bash
# permission-request.sh — Auto-approve safe commands, block dangerous ones
# Runs on: PermissionRequest
#
# Exit 0 = allow (auto-approve)
# Exit 2 = deny (block with reason on stdout)
# Any other exit = pass through to user (show normal permission dialog)
#
# Input JSON on stdin includes the tool name and arguments.

INPUT=$(cat)

# Extract the tool name
TOOL=$(echo "$INPUT" | grep -oP '"tool_name"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"tool_name"\s*:\s*"//;s/"$//' || true)

# Extract the command (for Bash tool calls)
COMMAND=$(echo "$INPUT" | grep -oP '"command"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"command"\s*:\s*"//;s/"$//' || true)

# ─── Auto-approve safe patterns ───────────────────────────────────────────────

if [[ "$TOOL" == "Read" ]] || [[ "$TOOL" == "Glob" ]] || [[ "$TOOL" == "Grep" ]]; then
  exit 0
fi

if [[ "$TOOL" == "Bash" ]]; then
  # Safe read-only commands
  case "$COMMAND" in
    git\ status*|git\ log*|git\ diff*|git\ branch*|git\ show*)
      exit 0 ;;
    npm\ test*|npx\ vitest*|npx\ jest*|npx\ playwright*)
      exit 0 ;;
    npm\ run\ lint*|npx\ eslint*|npx\ tsc\ --noEmit*)
      exit 0 ;;
    npm\ run\ build*|npm\ run\ dev*)
      exit 0 ;;
    ls\ *|pwd|cat\ *|head\ *|tail\ *|wc\ *)
      exit 0 ;;
    bash\ scripts/quality-gate.sh*)
      exit 0 ;;
  esac

  # ─── Block dangerous patterns ─────────────────────────────────────────────

  case "$COMMAND" in
    *rm\ -rf\ /*)
      echo "BLOCKED: rm -rf with absolute root path is too dangerous."
      exit 2 ;;
    *DROP\ TABLE*|*DROP\ DATABASE*|*TRUNCATE\ *)
      echo "BLOCKED: Destructive database operation. Use migrations instead."
      exit 2 ;;
    *--force*push*|*push*--force*|*push\ -f\ *)
      echo "BLOCKED: Force push can destroy remote history. Use --force-with-lease if needed."
      exit 2 ;;
    *git\ reset\ --hard\ origin/main*|*git\ reset\ --hard\ origin/master*)
      echo "BLOCKED: Hard reset to remote discards all local work. Are you sure?"
      exit 2 ;;
    *curl*-X\ DELETE*production*|*curl*-X\ DELETE*prod.*)
      echo "BLOCKED: DELETE request to production endpoint."
      exit 2 ;;
  esac
fi

# ─── Everything else: pass through to user ────────────────────────────────────

exit 1
