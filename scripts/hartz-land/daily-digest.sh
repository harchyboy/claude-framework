#!/bin/bash
# daily-digest.sh — Generate a summary of overnight Hartz Land activity
#
# Usage:
#   bash scripts/hartz-land/daily-digest.sh [options]
#
# Options:
#   --hours <n>      Look back N hours (default: 24)
#   --output <file>  Write digest to file instead of stdout
#   --json           Output as JSON
#   --help           Show this help
#
# Shows:
#   - Stories completed per project
#   - Verification results
#   - Review queue items needing attention
#   - Failures and blockers
#   - Cost summary (if telemetry enabled)

set -euo pipefail

HOURS=24
OUTPUT_FILE=""
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hours)   HOURS="$2"; shift ;;
    --output)  OUTPUT_FILE="$2"; shift ;;
    --json)    JSON_OUTPUT=true ;;
    --help)
      sed -n '2,17p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
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

# ─── Directories ─────────────────────────────────────────────────────────────

HARTZ_DIR="$HOME/.hartz-claude-framework"
LOG_DIR="$HARTZ_DIR/logs"
REVIEW_DIR="$HARTZ_DIR/review-queue"
REGISTRY="$HARTZ_DIR/projects.txt"

CUTOFF_TIMESTAMP=$(date -d "$HOURS hours ago" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || \
  node -e "console.log(new Date(Date.now() - $HOURS * 3600000).toISOString().slice(0,19))")

generate_digest() {
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}  HARTZ LAND — Daily Digest${NC}"
  echo -e "${BOLD}  $(date '+%A, %B %d %Y at %H:%M')${NC}"
  echo -e "${BOLD}  Looking back: ${HOURS} hours${NC}"
  echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
  echo ""

  TOTAL_STORIES_COMPLETED=0
  TOTAL_STORIES_REMAINING=0
  TOTAL_COST=0
  PROJECTS_WITH_ACTIVITY=0
  TOTAL_REVIEWS_PENDING=0

  if [[ ! -f "$REGISTRY" ]]; then
    echo "  No project registry found."
    return
  fi

  while IFS= read -r project_path; do
    [[ -z "$project_path" ]] && continue
    [[ "$project_path" == \#* ]] && continue
    [[ ! -d "$project_path" ]] && continue

    PROJECT_NAME=$(basename "$project_path")
    HAD_ACTIVITY=false

    # ─── Telemetry analysis ─────────────────────────────────────────

    TELEMETRY_FILE="$project_path/agent_logs/ralph-telemetry.jsonl"
    PROJECT_STORIES=0
    PROJECT_COST=0
    PROJECT_ITERATIONS=0
    PROJECT_FAILURES=""

    if [[ -f "$TELEMETRY_FILE" ]]; then
      # Parse recent telemetry events
      TELEMETRY_DATA=$(node -e "
        const fs = require('fs');
        const lines = fs.readFileSync('$TELEMETRY_FILE', 'utf8').trim().split('\n');
        const cutoff = '$CUTOFF_TIMESTAMP';
        let stories = 0, cost = 0, iterations = 0, failures = [];

        for (const line of lines) {
          try {
            const event = JSON.parse(line);
            if (event.timestamp < cutoff) continue;

            if (event.event === 'iteration_end') {
              iterations++;
              stories += (event.stories_completed || 0);
              cost += parseFloat(event.total_cost || 0);
              if (event.quality_gate === 'failed') {
                failures.push('Iteration ' + event.iteration + ': quality gate failed');
              }
            }
          } catch(e) {}
        }

        console.log(JSON.stringify({ stories, cost: Math.round(cost * 100) / 100, iterations, failures }));
      " 2>/dev/null || echo '{"stories":0,"cost":0,"iterations":0,"failures":[]}')

      PROJECT_STORIES=$(echo "$TELEMETRY_DATA" | node -e "process.stdin.on('data',d=>{const o=JSON.parse(d);console.log(o.stories)})" 2>/dev/null || echo "0")
      PROJECT_COST=$(echo "$TELEMETRY_DATA" | node -e "process.stdin.on('data',d=>{const o=JSON.parse(d);console.log(o.cost)})" 2>/dev/null || echo "0")
      PROJECT_ITERATIONS=$(echo "$TELEMETRY_DATA" | node -e "process.stdin.on('data',d=>{const o=JSON.parse(d);console.log(o.iterations)})" 2>/dev/null || echo "0")

      if [[ "$PROJECT_ITERATIONS" -gt 0 ]]; then
        HAD_ACTIVITY=true
      fi
    fi

    # ─── PRD status ─────────────────────────────────────────────────

    STORIES_TOTAL=0
    STORIES_DONE=0
    for prd_dir in "$project_path"/scripts/ralph-moss/prds/*/; do
      if [[ -f "$prd_dir/prd.json" ]]; then
        COUNTS=$(node -e "
          const prd = JSON.parse(require('fs').readFileSync('$prd_dir/prd.json', 'utf8'));
          console.log(prd.userStories.length + ':' + prd.userStories.filter(s => s.passes).length);
        " 2>/dev/null || echo "0:0")
        STORIES_TOTAL=$((STORIES_TOTAL + $(echo "$COUNTS" | cut -d: -f1)))
        STORIES_DONE=$((STORIES_DONE + $(echo "$COUNTS" | cut -d: -f2)))
      fi
    done

    STORIES_REMAINING=$((STORIES_TOTAL - STORIES_DONE))
    TOTAL_STORIES_COMPLETED=$((TOTAL_STORIES_COMPLETED + PROJECT_STORIES))
    TOTAL_STORIES_REMAINING=$((TOTAL_STORIES_REMAINING + STORIES_REMAINING))
    TOTAL_COST=$(node -e "console.log(Math.round(($TOTAL_COST + $PROJECT_COST) * 100) / 100)" 2>/dev/null || echo "$TOTAL_COST")

    # ─── Review queue ───────────────────────────────────────────────

    REVIEW_COUNT=0
    REVIEW_HIGH=0
    REVIEW_MED=0
    REVIEW_LOW=0

    for review_file in "$REVIEW_DIR/${PROJECT_NAME}"_*.json; do
      [[ ! -f "$review_file" ]] && continue
      REVIEW_COUNT=$((REVIEW_COUNT + 1))
      CONF=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$review_file','utf8')).confidence)" 2>/dev/null || echo "0")
      if (( $(node -e "console.log($CONF >= 0.9 ? 1 : 0)") )); then
        REVIEW_HIGH=$((REVIEW_HIGH + 1))
      elif (( $(node -e "console.log($CONF >= 0.7 ? 1 : 0)") )); then
        REVIEW_MED=$((REVIEW_MED + 1))
      else
        REVIEW_LOW=$((REVIEW_LOW + 1))
      fi
    done
    TOTAL_REVIEWS_PENDING=$((TOTAL_REVIEWS_PENDING + REVIEW_COUNT))

    # ─── Display project summary ─────────────────────────────────

    if [[ "$HAD_ACTIVITY" == "true" ]] || [[ "$REVIEW_COUNT" -gt 0 ]]; then
      PROJECTS_WITH_ACTIVITY=$((PROJECTS_WITH_ACTIVITY + 1))

      echo -e "  ${BOLD}$PROJECT_NAME${NC}"
      if [[ "$PROJECT_STORIES" -gt 0 ]]; then
        echo -e "    ${GREEN}+${PROJECT_STORIES} stories completed${NC} ($PROJECT_ITERATIONS iterations, \$${PROJECT_COST})"
      fi
      echo "    Progress: $STORIES_DONE/$STORIES_TOTAL stories ($STORIES_REMAINING remaining)"

      if [[ "$REVIEW_COUNT" -gt 0 ]]; then
        REVIEW_SUMMARY=""
        [[ "$REVIEW_HIGH" -gt 0 ]] && REVIEW_SUMMARY+="${GREEN}$REVIEW_HIGH high-confidence${NC} "
        [[ "$REVIEW_MED" -gt 0 ]] && REVIEW_SUMMARY+="${YELLOW}$REVIEW_MED medium${NC} "
        [[ "$REVIEW_LOW" -gt 0 ]] && REVIEW_SUMMARY+="${RED}$REVIEW_LOW needs attention${NC} "
        echo -e "    Review queue: $REVIEW_SUMMARY"
      fi

      echo ""
    fi

  done < "$REGISTRY"

  # ─── Overall summary ────────────────────────────────────────────

  echo -e "  ${BOLD}─────────────────────────────────────────${NC}"
  echo ""
  echo -e "  ${BOLD}SUMMARY${NC}"
  echo "  Stories completed (last ${HOURS}h):  $TOTAL_STORIES_COMPLETED"
  echo "  Stories remaining:               $TOTAL_STORIES_REMAINING"
  echo "  Total cost:                      \$$TOTAL_COST"
  echo "  Active projects:                 $PROJECTS_WITH_ACTIVITY"
  echo ""

  if [[ "$TOTAL_REVIEWS_PENDING" -gt 0 ]]; then
    echo -e "  ${YELLOW}${BOLD}ACTION NEEDED: $TOTAL_REVIEWS_PENDING items in review queue${NC}"
    echo "  Run: bash scripts/hartz-land/review-queue.sh"
  else
    echo -e "  ${GREEN}No items need your attention.${NC}"
  fi
  echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────

if [[ -n "$OUTPUT_FILE" ]]; then
  generate_digest > "$OUTPUT_FILE"
  echo "Digest written to $OUTPUT_FILE"
else
  generate_digest
fi
