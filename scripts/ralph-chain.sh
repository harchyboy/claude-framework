#!/bin/bash
# ralph-chain.sh — Runs Ralph loop repeatedly until all PRDs are complete
# Usage: bash scripts/ralph-chain.sh [ralph options...]
#
# Scans scripts/ralph-moss/prds/*/prd.json for incomplete stories.
# Runs Ralph for each PRD in sequence until all stories pass.

set -euo pipefail

RALPH_ARGS=("$@")
COMPLETED_PRDS=0
FAILED_PRDS=0
START_TIME=$(date +%s)

echo "═══════════════════════════════════════"
echo "RALPH CHAIN — Multi-PRD Autonomous Run"
echo "═══════════════════════════════════════"
echo "Args: ${RALPH_ARGS[*]:-none}"
echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

while true; do
  # Find next PRD with incomplete stories
  FOUND_PRD=""
  for dir in scripts/ralph-moss/prds/*/; do
    if [[ -f "$dir/prd.json" ]]; then
      incomplete=$(node -e "
        const prd = JSON.parse(require('fs').readFileSync('$dir/prd.json', 'utf8'));
        console.log(prd.userStories.filter(s => !s.passes && !s.stuck).length);
      " 2>/dev/null || echo "0")

      if [[ "$incomplete" -gt 0 ]]; then
        FOUND_PRD="$dir"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📋 Next PRD: $dir ($incomplete stories remaining)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        break
      fi
    fi
  done

  if [[ -z "$FOUND_PRD" ]]; then
    echo ""
    echo "═══════════════════════════════════════"
    echo "RALPH CHAIN COMPLETE"
    echo "═══════════════════════════════════════"
    break
  fi

  # Run Ralph — it will pick up the first PRD with incomplete stories
  # Ralph may exit non-zero even on success (e.g. summary script fails after all stories complete)
  RALPH_EXIT=0
  bash scripts/ralph.sh "${RALPH_ARGS[@]}" || RALPH_EXIT=$?

  # After Ralph, ensure we're on the main branch and have latest work
  git checkout master 2>/dev/null || git checkout main 2>/dev/null || true

  # Merge any Ralph branches that have new commits
  for ralph_branch in $(git branch --list 'ralph-moss/*' 2>/dev/null | tr -d ' *'); do
    if git log "HEAD..${ralph_branch}" --oneline 2>/dev/null | grep -q .; then
      echo "  🔀 Merging $ralph_branch into $(git branch --show-current)"
      git merge "$ralph_branch" --no-edit 2>/dev/null || true
    fi
    git branch -D "$ralph_branch" 2>/dev/null || true
  done
  git worktree prune 2>/dev/null || true

  if [[ "$RALPH_EXIT" -ne 0 ]]; then
    echo "⚠️  Ralph exited with code $RALPH_EXIT for $FOUND_PRD"

    # Check if PRD is actually complete despite the error
    remaining=$(node -e "
      const fs = require('fs');
      const f = '${FOUND_PRD}prd.json';
      if (!fs.existsSync(f)) { console.log('0'); process.exit(); }
      const prd = JSON.parse(fs.readFileSync(f, 'utf8'));
      console.log(prd.userStories.filter(s => !s.passes && !s.stuck).length);
    " 2>/dev/null || echo "0")

    if [[ "$remaining" -gt 0 ]]; then
      FAILED_PRDS=$((FAILED_PRDS + 1))
      echo "❌ $remaining stories still incomplete in $FOUND_PRD"
      # Check for stuck stories — Ralph should have already flagged them
      stuck=$(node -e "
        const prd = JSON.parse(require('fs').readFileSync('${FOUND_PRD}prd.json', 'utf8'));
        prd.userStories.filter(s => s.stuck).forEach(s => console.log('  🚨 STUCK: ' + s.id + ' — ' + (s.stuckReason || 'unknown')));
      " 2>/dev/null || true)
      [[ -n "$stuck" ]] && echo "$stuck"
    else
      echo "✅ All stories complete despite exit code — continuing"
    fi
  fi

  # Check if that PRD is now complete
  still_remaining=$(node -e "
    const fs = require('fs');
    const f = '${FOUND_PRD}prd.json';
    if (!fs.existsSync(f)) { console.log('0'); process.exit(); }
    const prd = JSON.parse(fs.readFileSync(f, 'utf8'));
    console.log(prd.userStories.filter(s => !s.passes).length);
  " 2>/dev/null || echo "0")

  if [[ "$still_remaining" -eq 0 ]]; then
    COMPLETED_PRDS=$((COMPLETED_PRDS + 1))
    echo "✅ PRD complete: $FOUND_PRD"
  fi

  echo ""
  echo "⏳ Cooling down 10s before next PRD..."
  sleep 10
done

END_TIME=$(date +%s)
ELAPSED=$(( (END_TIME - START_TIME) / 60 ))

echo "PRDs completed:  $COMPLETED_PRDS"
echo "PRDs failed:     $FAILED_PRDS"
echo "Total time:      ${ELAPSED} minutes"
echo ""
