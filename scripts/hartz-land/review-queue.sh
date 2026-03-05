#!/bin/bash
# review-queue.sh — Manage the human review queue for verified stories
#
# Usage:
#   bash scripts/hartz-land/review-queue.sh [command] [options]
#
# Commands:
#   list              Show all items in the review queue (default)
#   approve <id>      Approve a story (marks as reviewed)
#   reject <id>       Reject a story (marks for rework)
#   auto-approve      Auto-approve all high-confidence (>0.9) items
#   clear             Remove all reviewed items from the queue
#   stats             Show queue statistics
#
# Options:
#   --project <name>  Filter to a specific project
#   --min-confidence  Minimum confidence to show (default: 0)
#   --json            Output in JSON format
#   --help            Show this help

set -euo pipefail

COMMAND="${1:-list}"
[[ "$COMMAND" == --* ]] && COMMAND="list"
[[ "$COMMAND" != --* ]] && shift || true

STORY_ID=""
SPECIFIC_PROJECT=""
MIN_CONFIDENCE=0
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)        SPECIFIC_PROJECT="$2"; shift ;;
    --min-confidence) MIN_CONFIDENCE="$2"; shift ;;
    --json)           JSON_OUTPUT=true ;;
    --help)
      sed -n '2,17p' "$0"
      exit 0
      ;;
    *)
      if [[ -z "$STORY_ID" ]] && [[ "$1" != --* ]]; then
        STORY_ID="$1"
      fi
      ;;
  esac
  shift
done

# ─── Colours ──────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  ✅ $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠️  $1${NC}"; }
err()  { echo -e "${RED}  ❌ $1${NC}"; }

REVIEW_DIR="$HOME/.hartz-claude-framework/review-queue"
mkdir -p "$REVIEW_DIR"

# ─── List ─────────────────────────────────────────────────────────────────────

list_queue() {
  echo ""
  echo -e "${BOLD}  Review Queue${NC}"
  echo -e "  ${DIM}─────────────────────────────────────────────────────${NC}"
  echo ""

  HIGH=0
  MEDIUM=0
  LOW=0
  TOTAL=0
  REVIEWED=0

  for review_file in "$REVIEW_DIR"/*.json; do
    [[ ! -f "$review_file" ]] && continue

    ENTRY=$(cat "$review_file")
    PROJECT=$(echo "$ENTRY" | node -e "process.stdin.on('data',d=>{console.log(JSON.parse(d).project)})")
    SID=$(echo "$ENTRY" | node -e "process.stdin.on('data',d=>{console.log(JSON.parse(d).story_id)})")
    CONF=$(echo "$ENTRY" | node -e "process.stdin.on('data',d=>{console.log(JSON.parse(d).confidence)})")
    VERDICT=$(echo "$ENTRY" | node -e "process.stdin.on('data',d=>{console.log(JSON.parse(d).verdict)})")
    IS_REVIEWED=$(echo "$ENTRY" | node -e "process.stdin.on('data',d=>{console.log(JSON.parse(d).reviewed)})")
    TIMESTAMP=$(echo "$ENTRY" | node -e "process.stdin.on('data',d=>{console.log(JSON.parse(d).timestamp)})")
    PROOF_PATH=$(echo "$ENTRY" | node -e "process.stdin.on('data',d=>{console.log(JSON.parse(d).proof_path)})")

    # Filters
    if [[ -n "$SPECIFIC_PROJECT" ]] && [[ "$PROJECT" != "$SPECIFIC_PROJECT" ]]; then
      continue
    fi

    if (( $(node -e "console.log($CONF < $MIN_CONFIDENCE ? 1 : 0)") )); then
      continue
    fi

    if [[ "$IS_REVIEWED" == "true" ]]; then
      REVIEWED=$((REVIEWED + 1))
      continue
    fi

    TOTAL=$((TOTAL + 1))

    # Confidence category
    CONF_LABEL=""
    if (( $(node -e "console.log($CONF >= 0.9 ? 1 : 0)") )); then
      CONF_LABEL="${GREEN}HIGH${NC}"
      HIGH=$((HIGH + 1))
    elif (( $(node -e "console.log($CONF >= 0.7 ? 1 : 0)") )); then
      CONF_LABEL="${YELLOW}MED${NC}"
      MEDIUM=$((MEDIUM + 1))
    else
      CONF_LABEL="${RED}LOW${NC}"
      LOW=$((LOW + 1))
    fi

    # Verdict icon
    if [[ "$VERDICT" == "PASS" ]]; then
      VERDICT_ICON="${GREEN}PASS${NC}"
    else
      VERDICT_ICON="${RED}FAIL${NC}"
    fi

    echo -e "  [$CONF_LABEL] ${BOLD}$PROJECT${NC} / $SID"
    echo -e "       Verdict: $VERDICT_ICON  Confidence: $CONF"
    echo -e "       Time: $TIMESTAMP"
    echo -e "       Proof: $PROOF_PATH"
    echo ""
  done

  if [[ "$TOTAL" -eq 0 ]]; then
    echo -e "  ${GREEN}Queue is empty — nothing needs review.${NC}"
  else
    echo -e "  ${DIM}─────────────────────────────────────────────────────${NC}"
    echo -e "  Total: $TOTAL  ${GREEN}High: $HIGH${NC}  ${YELLOW}Med: $MEDIUM${NC}  ${RED}Low: $LOW${NC}"
    echo ""
    if [[ "$HIGH" -gt 0 ]]; then
      echo -e "  ${GREEN}$HIGH items are auto-approve candidates.${NC}"
      echo "  Run: bash scripts/hartz-land/review-queue.sh auto-approve"
    fi
  fi
  echo ""
}

# ─── Approve ──────────────────────────────────────────────────────────────────

approve_story() {
  local target="$1"
  local found=false

  for review_file in "$REVIEW_DIR"/*.json; do
    [[ ! -f "$review_file" ]] && continue
    SID=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$review_file','utf8')).story_id)")
    if [[ "$SID" == "$target" ]]; then
      node -e "
        const f = '$review_file';
        const entry = JSON.parse(require('fs').readFileSync(f, 'utf8'));
        entry.reviewed = true;
        entry.review_action = 'approved';
        entry.review_timestamp = new Date().toISOString();
        require('fs').writeFileSync(f, JSON.stringify(entry, null, 2));
      "
      ok "Approved: $target"
      found=true
      break
    fi
  done

  if [[ "$found" != "true" ]]; then
    err "Story not found in review queue: $target"
  fi
}

# ─── Reject ───────────────────────────────────────────────────────────────────

reject_story() {
  local target="$1"
  local found=false

  for review_file in "$REVIEW_DIR"/*.json; do
    [[ ! -f "$review_file" ]] && continue
    SID=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$review_file','utf8')).story_id)")
    if [[ "$SID" == "$target" ]]; then
      node -e "
        const f = '$review_file';
        const entry = JSON.parse(require('fs').readFileSync(f, 'utf8'));
        entry.reviewed = true;
        entry.review_action = 'rejected';
        entry.review_timestamp = new Date().toISOString();
        require('fs').writeFileSync(f, JSON.stringify(entry, null, 2));
      "
      warn "Rejected: $target (queued for rework)"
      found=true
      break
    fi
  done

  if [[ "$found" != "true" ]]; then
    err "Story not found in review queue: $target"
  fi
}

# ─── Auto-approve ─────────────────────────────────────────────────────────────

auto_approve() {
  local approved=0

  for review_file in "$REVIEW_DIR"/*.json; do
    [[ ! -f "$review_file" ]] && continue

    ENTRY=$(cat "$review_file")
    IS_REVIEWED=$(echo "$ENTRY" | node -e "process.stdin.on('data',d=>{console.log(JSON.parse(d).reviewed)})")
    CONF=$(echo "$ENTRY" | node -e "process.stdin.on('data',d=>{console.log(JSON.parse(d).confidence)})")
    VERDICT=$(echo "$ENTRY" | node -e "process.stdin.on('data',d=>{console.log(JSON.parse(d).verdict)})")
    SID=$(echo "$ENTRY" | node -e "process.stdin.on('data',d=>{console.log(JSON.parse(d).story_id)})")
    PROJECT=$(echo "$ENTRY" | node -e "process.stdin.on('data',d=>{console.log(JSON.parse(d).project)})")

    if [[ "$IS_REVIEWED" == "true" ]]; then continue; fi
    if [[ "$VERDICT" != "PASS" ]]; then continue; fi

    if (( $(node -e "console.log($CONF >= 0.9 ? 1 : 0)") )); then
      node -e "
        const f = '$review_file';
        const entry = JSON.parse(require('fs').readFileSync(f, 'utf8'));
        entry.reviewed = true;
        entry.review_action = 'auto-approved';
        entry.review_timestamp = new Date().toISOString();
        require('fs').writeFileSync(f, JSON.stringify(entry, null, 2));
      "
      ok "Auto-approved: $PROJECT / $SID (confidence: $CONF)"
      approved=$((approved + 1))
    fi
  done

  echo ""
  echo "  Auto-approved: $approved items"
}

# ─── Clear ────────────────────────────────────────────────────────────────────

clear_reviewed() {
  local cleared=0

  for review_file in "$REVIEW_DIR"/*.json; do
    [[ ! -f "$review_file" ]] && continue
    IS_REVIEWED=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$review_file','utf8')).reviewed)")
    if [[ "$IS_REVIEWED" == "true" ]]; then
      rm -f "$review_file"
      cleared=$((cleared + 1))
    fi
  done

  ok "Cleared $cleared reviewed items from queue"
}

# ─── Stats ────────────────────────────────────────────────────────────────────

show_stats() {
  echo ""
  echo -e "${BOLD}  Review Queue Statistics${NC}"
  echo ""

  node -e "
    const fs = require('fs');
    const dir = '$REVIEW_DIR';
    const files = fs.readdirSync(dir).filter(f => f.endsWith('.json'));

    let total = 0, reviewed = 0, pending = 0;
    let high = 0, med = 0, low = 0;
    let passed = 0, failed = 0;
    let approved = 0, rejected = 0, autoApproved = 0;
    const projects = {};

    for (const f of files) {
      const entry = JSON.parse(fs.readFileSync(dir + '/' + f, 'utf8'));
      total++;

      if (!projects[entry.project]) projects[entry.project] = { total: 0, reviewed: 0 };
      projects[entry.project].total++;

      if (entry.reviewed) {
        reviewed++;
        projects[entry.project].reviewed++;
        if (entry.review_action === 'approved') approved++;
        else if (entry.review_action === 'rejected') rejected++;
        else if (entry.review_action === 'auto-approved') autoApproved++;
      } else {
        pending++;
        if (entry.confidence >= 0.9) high++;
        else if (entry.confidence >= 0.7) med++;
        else low++;
      }

      if (entry.verdict === 'PASS') passed++;
      else failed++;
    }

    console.log('  Total items:     ' + total);
    console.log('  Pending review:  ' + pending);
    console.log('  Reviewed:        ' + reviewed);
    console.log('    Approved:      ' + approved);
    console.log('    Auto-approved: ' + autoApproved);
    console.log('    Rejected:      ' + rejected);
    console.log('');
    console.log('  Pending by confidence:');
    console.log('    High (>0.9):   ' + high);
    console.log('    Medium:        ' + med);
    console.log('    Low (<0.7):    ' + low);
    console.log('');
    console.log('  Verdicts:');
    console.log('    Passed:        ' + passed);
    console.log('    Failed:        ' + failed);
    console.log('');
    console.log('  By project:');
    for (const [p, s] of Object.entries(projects)) {
      console.log('    ' + p + ': ' + s.total + ' total, ' + s.reviewed + ' reviewed');
    }
  "
  echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────

case "$COMMAND" in
  list)         list_queue ;;
  approve)
    if [[ -z "$STORY_ID" ]]; then err "Usage: review-queue.sh approve <story-id>"; exit 1; fi
    approve_story "$STORY_ID"
    ;;
  reject)
    if [[ -z "$STORY_ID" ]]; then err "Usage: review-queue.sh reject <story-id>"; exit 1; fi
    reject_story "$STORY_ID"
    ;;
  auto-approve) auto_approve ;;
  clear)        clear_reviewed ;;
  stats)        show_stats ;;
  *)
    err "Unknown command: $COMMAND"
    sed -n '2,17p' "$0"
    exit 1
    ;;
esac
