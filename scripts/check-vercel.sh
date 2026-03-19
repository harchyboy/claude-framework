#!/bin/bash
# check-vercel.sh — Check Vercel build and runtime logs for errors
# Hartz Claude Framework
#
# Usage:
#   bash scripts/check-vercel.sh              # Check current project
#   bash scripts/check-vercel.sh --all        # Check all Vercel projects
#   bash scripts/check-vercel.sh --json       # Output as JSON
#   bash scripts/check-vercel.sh --runtime 60 # Check last 60 mins of runtime logs
#
# Requires: VERCEL_TOKEN environment variable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/vercel-logs.sh"

CHECK_ALL=false
JSON_OUTPUT=false
RUNTIME_MINUTES=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)     CHECK_ALL=true ;;
    --json)    JSON_OUTPUT=true ;;
    --runtime) RUNTIME_MINUTES="$2"; shift ;;
    --help)
      sed -n '2,10p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

vercel_check_token || exit 1

if [[ "$CHECK_ALL" == "true" ]]; then
  # Check all Vercel projects
  echo "═══════════════════════════════════════"
  echo "VERCEL STATUS — ALL PROJECTS"
  echo "═══════════════════════════════════════"
  echo ""

  ALL_RESULTS="["
  FIRST=true

  PROJECTS=$(vercel_api "/v9/projects?limit=50" | node -e "
    const d = JSON.parse(require('fs').readFileSync(0,'utf8'));
    (d.projects || []).forEach(p => console.log(p.id + '|' + p.name));
  " 2>/dev/null || echo "")

  while IFS='|' read -r proj_id proj_name; do
    [[ -z "$proj_id" ]] && continue

    DEP_JSON=$(vercel_get_latest_deployment "$proj_id")
    DEP_STATE=$(echo "$DEP_JSON" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync(0,'utf8')).state || 'UNKNOWN')" 2>/dev/null || echo "UNKNOWN")
    DEP_URL=$(echo "$DEP_JSON" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync(0,'utf8')).url || '')" 2>/dev/null || echo "")
    DEP_ERROR=$(echo "$DEP_JSON" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync(0,'utf8')).error || '')" 2>/dev/null || echo "")

    if [[ "$DEP_STATE" == "READY" ]]; then
      ICON="✅"
    elif [[ "$DEP_STATE" == "ERROR" ]]; then
      ICON="❌"
    elif [[ "$DEP_STATE" == "BUILDING" ]] || [[ "$DEP_STATE" == "QUEUED" ]]; then
      ICON="🔄"
    else
      ICON="⚠️ "
    fi

    if [[ "$JSON_OUTPUT" != "true" ]]; then
      echo "  $ICON $proj_name — $DEP_STATE"
      [[ -n "$DEP_URL" ]] && echo "     https://$DEP_URL"
      [[ -n "$DEP_ERROR" ]] && echo "     Error: $DEP_ERROR"
    fi

    if [[ "$FIRST" == "true" ]]; then FIRST=false; else ALL_RESULTS+=","; fi
    ALL_RESULTS+="{\"name\":\"$proj_name\",\"id\":\"$proj_id\",\"state\":\"$DEP_STATE\",\"url\":\"$DEP_URL\",\"error\":\"$DEP_ERROR\"}"
  done <<< "$PROJECTS"

  ALL_RESULTS+="]"

  if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo "$ALL_RESULTS" | node -e "process.stdout.write(JSON.stringify(JSON.parse(require('fs').readFileSync(0,'utf8')),null,2)+'\n')" 2>/dev/null || echo "$ALL_RESULTS"
  else
    echo ""
  fi
else
  # Check current project only
  echo "═══════════════════════════════════════"
  echo "VERCEL STATUS — $(basename "$(pwd)")"
  echo "═══════════════════════════════════════"
  echo ""

  mkdir -p agent_logs
  vercel_diagnose_deployment "agent_logs"
  echo ""
fi
