#!/usr/bin/env bash
# governance-capture.sh — Audit trail for governance-relevant tool actions
# Runs on: PostToolUse (all tools)
# Enable: Set HCF_GOVERNANCE_CAPTURE=1 in environment
# Logs to: .claude/governance/audit.log
#
# Tracks: file deletions, secret-like patterns, permission changes,
# database operations, and external service calls.

set -euo pipefail

# Skip if governance capture is disabled
[[ "${HCF_GOVERNANCE_CAPTURE:-0}" != "1" ]] && exit 0

# Read tool input from stdin
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")
TOOL_INPUT=$(echo "$INPUT" | python -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d.get('tool_input',{})))" 2>/dev/null || echo "{}")

[[ -z "$TOOL_NAME" ]] && exit 0

GOVERNANCE_DIR=".claude/governance"
AUDIT_LOG="$GOVERNANCE_DIR/audit.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

mkdir -p "$GOVERNANCE_DIR"

governance_log() {
  local severity="$1"
  local category="$2"
  local detail="$3"
  echo "$TIMESTAMP | $severity | $category | tool=$TOOL_NAME | branch=$BRANCH | $detail" >> "$AUDIT_LOG"
}

# ─── Detect governance-relevant patterns ─────────────────────────────────────

case "$TOOL_NAME" in
  Bash)
    COMMAND=$(echo "$TOOL_INPUT" | python -c "import sys,json; print(json.load(sys.stdin).get('command',''))" 2>/dev/null || echo "")

    # Destructive operations
    if echo "$COMMAND" | grep -qE '(rm -rf|drop table|drop database|git push --force|git reset --hard)'; then
      governance_log "WARN" "destructive-op" "command=$COMMAND"
    fi

    # Secret/credential patterns
    if echo "$COMMAND" | grep -qiE '(api.key|secret|password|token|credential|private.key)'; then
      governance_log "WARN" "secret-adjacent" "command involves secret-like patterns"
    fi

    # External service calls
    if echo "$COMMAND" | grep -qE '(curl|wget|fetch|http|https)'; then
      governance_log "INFO" "external-call" "command=$COMMAND"
    fi

    # Database operations
    if echo "$COMMAND" | grep -qiE '(psql|mysql|mongo|redis-cli|supabase|prisma migrate)'; then
      governance_log "INFO" "database-op" "command=$COMMAND"
    fi

    # Permission changes
    if echo "$COMMAND" | grep -qE '(chmod|chown|chgrp|setfacl)'; then
      governance_log "INFO" "permission-change" "command=$COMMAND"
    fi
    ;;

  Write|Edit)
    FILE_PATH=$(echo "$TOOL_INPUT" | python -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null || echo "")

    # Sensitive file modifications
    if echo "$FILE_PATH" | grep -qiE '(\.env|secret|credential|password|\.pem|\.key|auth|token)'; then
      governance_log "WARN" "sensitive-file" "path=$FILE_PATH"
    fi

    # Config file modifications
    if echo "$FILE_PATH" | grep -qiE '(settings\.json|config\.|\.yml|\.yaml|Dockerfile|docker-compose)'; then
      governance_log "INFO" "config-change" "path=$FILE_PATH"
    fi

    # Migration files
    if echo "$FILE_PATH" | grep -qiE '(migration|schema|\.sql)'; then
      governance_log "INFO" "schema-change" "path=$FILE_PATH"
    fi
    ;;
esac

exit 0
