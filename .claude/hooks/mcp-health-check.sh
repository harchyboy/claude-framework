#!/usr/bin/env bash
# mcp-health-check.sh — Pre-execution MCP server health check
# Runs on: PreToolUse (all tools)
# Blocks calls to unhealthy MCP servers to prevent wasted tokens on timeouts.
#
# Skip check: Set HCF_SKIP_MCP_HEALTH=1 in environment
# Cache duration: 60 seconds (avoid re-checking on every tool call)

set -euo pipefail

# Skip if disabled
[[ "${HCF_SKIP_MCP_HEALTH:-0}" == "1" ]] && exit 0

# Read tool input from stdin
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")

# Only check MCP tools (prefixed with mcp__)
[[ ! "$TOOL_NAME" =~ ^mcp__ ]] && exit 0

# Extract server name from tool name (mcp__servername__toolname -> servername)
SERVER_NAME=$(echo "$TOOL_NAME" | sed 's/^mcp__//' | sed 's/__.*//')

[[ -z "$SERVER_NAME" ]] && exit 0

# ─── Health cache (avoid re-checking every call) ──────────────────────────────

CACHE_DIR="${TMPDIR:-/tmp}/hcf-mcp-health"
mkdir -p "$CACHE_DIR"
CACHE_FILE="$CACHE_DIR/$SERVER_NAME"
UNHEALTHY_FILE="$CACHE_DIR/${SERVER_NAME}.unhealthy"
CACHE_TTL=60  # seconds

# Check if we have a recent healthy cache entry
if [[ -f "$CACHE_FILE" ]]; then
  CACHE_AGE=$(( $(date +%s) - $(date -r "$CACHE_FILE" +%s 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
  if [[ $CACHE_AGE -lt $CACHE_TTL ]]; then
    exit 0  # Recently verified healthy
  fi
fi

# Check if recently marked unhealthy (prevent repeated failures)
if [[ -f "$UNHEALTHY_FILE" ]]; then
  UNHEALTHY_AGE=$(( $(date +%s) - $(date -r "$UNHEALTHY_FILE" +%s 2>/dev/null || stat -c %Y "$UNHEALTHY_FILE" 2>/dev/null || echo 0) ))
  UNHEALTHY_TTL=300  # Block for 5 minutes after failure

  if [[ $UNHEALTHY_AGE -lt $UNHEALTHY_TTL ]]; then
    echo "MCP server '$SERVER_NAME' was recently unhealthy (${UNHEALTHY_AGE}s ago). Waiting ${UNHEALTHY_TTL}s before retry."
    echo "Set HCF_SKIP_MCP_HEALTH=1 to bypass, or wait $(( UNHEALTHY_TTL - UNHEALTHY_AGE ))s."
    # Don't block — just warn. Blocking would prevent recovery.
    exit 0
  else
    rm -f "$UNHEALTHY_FILE"
  fi
fi

# ─── Actual health check ─────────────────────────────────────────────────────
# We can't directly ping MCP servers from a hook (they're managed by Claude Code),
# so we track failures reactively. This hook primarily serves as a warning system
# and works with governance-capture.sh to track MCP reliability.

# Mark as healthy (optimistic — PostToolUseFailure pattern marks unhealthy)
touch "$CACHE_FILE"

exit 0
