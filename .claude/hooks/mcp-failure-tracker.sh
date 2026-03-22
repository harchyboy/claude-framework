#!/usr/bin/env bash
# mcp-failure-tracker.sh — Track MCP tool failures for health monitoring
# Runs on: PostToolUse (all tools)
# Works with mcp-health-check.sh to build a reliability picture.
#
# When an MCP tool call fails, this marks the server as unhealthy
# so mcp-health-check.sh can warn on subsequent calls.

set -euo pipefail

# Skip if health checks are disabled
[[ "${HCF_SKIP_MCP_HEALTH:-0}" == "1" ]] && exit 0

# Read tool result from stdin
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")
WAS_ERROR=$(echo "$INPUT" | python -c "import sys,json; d=json.load(sys.stdin); print('true' if d.get('error') or d.get('is_error') else 'false')" 2>/dev/null || echo "false")

# Only track MCP tools
[[ ! "$TOOL_NAME" =~ ^mcp__ ]] && exit 0

# Extract server name
SERVER_NAME=$(echo "$TOOL_NAME" | sed 's/^mcp__//' | sed 's/__.*//')
[[ -z "$SERVER_NAME" ]] && exit 0

CACHE_DIR="${TMPDIR:-/tmp}/hcf-mcp-health"
mkdir -p "$CACHE_DIR"

if [[ "$WAS_ERROR" == "true" ]]; then
  # Mark server as unhealthy
  touch "$CACHE_DIR/${SERVER_NAME}.unhealthy"
  rm -f "$CACHE_DIR/$SERVER_NAME"  # Remove healthy cache

  # Log the failure
  GOVERNANCE_DIR=".claude/governance"
  if [[ -d "$GOVERNANCE_DIR" ]] || [[ "${HCF_GOVERNANCE_CAPTURE:-0}" == "1" ]]; then
    mkdir -p "$GOVERNANCE_DIR"
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") | WARN | mcp-failure | server=$SERVER_NAME tool=$TOOL_NAME" >> "$GOVERNANCE_DIR/audit.log"
  fi
else
  # Mark server as healthy
  touch "$CACHE_DIR/$SERVER_NAME"
  rm -f "$CACHE_DIR/${SERVER_NAME}.unhealthy"
fi

exit 0
