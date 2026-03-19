#!/bin/bash
# consensus-gate.sh — Evaluate agent review verdicts and emit APPROVED or BLOCKED
# Hartz Claude Framework
#
# Usage: bash scripts/consensus-gate.sh [options]
#
# Options:
#   --threshold <n>   Minimum approval percentage required (default: 75)
#   --json <file>     Path to JSON verdict file (default: read from stdin)
#   --quiet           Suppress detailed output; print only APPROVED or BLOCKED
#   --help            Show this help
#
# Input JSON format:
#   {
#     "threshold": 75,
#     "agents": [
#       {"name": "security-sentinel",      "verdict": "APPROVE",         "p1_count": 0},
#       {"name": "typescript-reviewer",    "verdict": "REQUEST_CHANGES", "p1_count": 1},
#       {"name": "architecture-strategist","verdict": "APPROVE",         "p1_count": 0}
#     ]
#   }
#
# Verdict values: APPROVE | REQUEST_CHANGES | ABSTAIN
#
# Formula:
#   consensus = (APPROVE count) / (APPROVE + REQUEST_CHANGES count) * 100
#   ABSTAIN agents are excluded from the denominator.
#   If every agent ABSTAINs the result is BLOCKED.
#   Any agent with p1_count > 0 forces BLOCKED regardless of consensus %.
#
# Exit codes:
#   0 = APPROVED
#   1 = BLOCKED

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────

THRESHOLD=75
THRESHOLD_EXPLICIT=false
JSON_FILE=""
QUIET=false
OUTPUT_JSON=false

# ─── Colours ─────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Helpers ─────────────────────────────────────────────────────────────────

log()  { [[ "$QUIET" == "true" ]] || echo -e "$1"; }

show_help() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed -n '/^consensus-gate/,/^Exit codes/{ p; /^Exit codes/{n;p;n;p} }'
  # Fallback: just print all header comments
  grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'
  exit 0
}

# ─── Argument parsing ────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold)
      THRESHOLD="${2:?--threshold requires a numeric argument}"
      THRESHOLD_EXPLICIT=true
      shift 2
      ;;
    --json)
      JSON_FILE="${2:?--json requires a file path}"
      shift 2
      ;;
    --quiet)
      QUIET=true
      shift
      ;;
    --output-json)
      OUTPUT_JSON=true
      QUIET=true
      shift
      ;;
    --help|-h)
      grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
  esac
done

# ─── Read JSON input ─────────────────────────────────────────────────────────

if [[ -n "$JSON_FILE" ]]; then
  if [[ ! -f "$JSON_FILE" ]]; then
    echo "Error: JSON file not found: $JSON_FILE" >&2
    exit 1
  fi
  JSON_INPUT=$(cat "$JSON_FILE")
else
  if [[ -t 0 ]]; then
    echo "Error: no --json file specified and stdin is a terminal." >&2
    echo "Pipe JSON input or use --json <file>." >&2
    exit 1
  fi
  JSON_INPUT=$(cat)
fi

# Write to a temp file so Node can read it cleanly (avoids shell escaping issues)
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT
printf '%s' "$JSON_INPUT" > "$TMPFILE"

# ─── Parse + evaluate with Node ──────────────────────────────────────────────

RESULT=$(node -e "
const fs   = require('fs');
const path = process.argv[1];
const cli_threshold = parseInt(process.argv[2], 10);
const threshold_explicit = process.argv[3] === 'true';

let data;
try {
  data = JSON.parse(fs.readFileSync(path, 'utf8'));
} catch (e) {
  process.stderr.write('Error: invalid JSON — ' + e.message + '\n');
  process.exit(1);
}

const agents = Array.isArray(data.agents) ? data.agents : [];
const json_threshold = typeof data.threshold === 'number' ? data.threshold : 75;
// CLI --threshold takes precedence over JSON field
const threshold = threshold_explicit ? cli_threshold : json_threshold;

let approveCount = 0;
let requestCount = 0;
let abstainCount = 0;
let p1Veto       = false;
const p1VetoAgents = [];
const agentLines   = [];

for (const agent of agents) {
  const v  = String(agent.verdict || '').toUpperCase();
  const p1 = Number(agent.p1_count) || 0;

  if (v === 'APPROVE')            approveCount++;
  else if (v === 'REQUEST_CHANGES') requestCount++;
  else                              abstainCount++;

  if (p1 > 0) {
    p1Veto = true;
    p1VetoAgents.push(agent.name);
  }

  agentLines.push({ name: agent.name, verdict: v, p1_count: p1 });
}

const denominator = approveCount + requestCount;
const allAbstain  = denominator === 0;
const consensus   = allAbstain ? 0 : Math.round((approveCount / denominator) * 100);

let status, reason;
if (p1Veto) {
  status = 'BLOCKED';
  reason = 'P1_VETO';
} else if (allAbstain) {
  status = 'BLOCKED';
  reason = 'ALL_ABSTAIN';
} else if (consensus >= threshold) {
  status = 'APPROVED';
  reason = '';
} else {
  status = 'BLOCKED';
  reason = 'BELOW_THRESHOLD';
}

process.stdout.write(JSON.stringify({
  status,
  reason,
  consensus,
  threshold,
  approve_count:          approveCount,
  request_changes_count:  requestCount,
  abstain_count:          abstainCount,
  p1_veto:                p1Veto,
  p1_veto_agents:         p1VetoAgents,
  agent_lines:            agentLines
}) + '\n');
" "$TMPFILE" "$THRESHOLD" "$THRESHOLD_EXPLICIT") || exit 1

# ─── Extract fields via Node (safe — no shell-escaping of JSON values) ───────

_field() {
  # Usage: _field <key>
  # Reads RESULT from stdin via heredoc; Node extracts the named key.
  node -e "
    const d = JSON.parse(require('fs').readFileSync(0, 'utf8'));
    process.stdout.write(String(d['$1'] !== undefined ? d['$1'] : ''));
  " <<< "$RESULT"
}

STATUS=$(        _field status)
REASON=$(         _field reason)
CONSENSUS=$(      _field consensus)
THRESHOLD_USED=$( _field threshold)
APPROVE_COUNT=$(  _field approve_count)
RC_COUNT=$(       _field request_changes_count)
ABSTAIN_COUNT=$(  _field abstain_count)
P1_VETO=$(        _field p1_veto)
P1_VETO_AGENTS=$( node -e "
  const d = JSON.parse(require('fs').readFileSync(0,'utf8'));
  process.stdout.write(d.p1_veto_agents.join(', '));
" <<< "$RESULT")

# ─── Detailed output (suppressed by --quiet) ─────────────────────────────────

if [[ "$QUIET" != "true" ]]; then
  log ""
  log "═══════════════════════════════════════"
  log "CONSENSUS GATE"
  log "═══════════════════════════════════════"
  log ""

  # Per-agent verdict rows
  while IFS= read -r agent_json; do
    ANAME=$(   node -e "process.stdout.write(JSON.parse(process.argv[1]).name)"              -- "$agent_json")
    AVERDICT=$(node -e "process.stdout.write(JSON.parse(process.argv[1]).verdict)"           -- "$agent_json")
    AP1=$(     node -e "process.stdout.write(String(JSON.parse(process.argv[1]).p1_count))"  -- "$agent_json")

    case "$AVERDICT" in
      APPROVE)
        log "  ${GREEN}APPROVE${NC}          ${ANAME}"
        ;;
      REQUEST_CHANGES)
        P1_TAG=""
        [[ "$AP1" != "0" ]] && P1_TAG=" ${RED}[P1 x${AP1}]${NC}"
        log "  ${RED}REQUEST_CHANGES${NC}  ${ANAME}${P1_TAG}"
        ;;
      ABSTAIN)
        log "  ${YELLOW}ABSTAIN${NC}          ${ANAME}"
        ;;
      *)
        log "  ${YELLOW}UNKNOWN${NC}          ${ANAME} (verdict: ${AVERDICT})"
        ;;
    esac
  done < <(node -e "
    const d = JSON.parse(require('fs').readFileSync(0,'utf8'));
    d.agent_lines.forEach(a => console.log(JSON.stringify(a)));
  " <<< "$RESULT")

  log ""
  log "───────────────────────────────────────"
  log "  Approve:         ${APPROVE_COUNT}"
  log "  Request changes: ${RC_COUNT}"
  log "  Abstain:         ${ABSTAIN_COUNT}"
  log ""
  log "  Consensus:       ${CONSENSUS}%  (threshold: ${THRESHOLD_USED}%)"

  if [[ "$P1_VETO" == "true" ]]; then
    log "  ${RED}P1 veto by:      ${P1_VETO_AGENTS}${NC}"
  fi

  log ""
  log "───────────────────────────────────────"

  if [[ "$STATUS" == "APPROVED" ]]; then
    log "${GREEN}CONSENSUS GATE: APPROVED${NC}"
  else
    log "${RED}CONSENSUS GATE: BLOCKED${NC}"
    case "$REASON" in
      P1_VETO)         log "  Reason: P1 issue(s) filed — changes required before merge." ;;
      ALL_ABSTAIN)     log "  Reason: All agents abstained — no consensus formed." ;;
      BELOW_THRESHOLD) log "  Reason: Consensus ${CONSENSUS}% is below the ${THRESHOLD_USED}% threshold." ;;
    esac
  fi

  log ""
fi

# ─── Quiet / JSON output ─────────────────────────────────────────────────────

if [[ "$OUTPUT_JSON" == "true" ]]; then
  echo "$RESULT"
elif [[ "$QUIET" == "true" ]]; then
  echo "$STATUS"
fi

# ─── Exit code ───────────────────────────────────────────────────────────────

[[ "$STATUS" == "APPROVED" ]] && exit 0 || exit 1
