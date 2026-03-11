# /babysit — Autonomous Run Monitor (loop-friendly)

Lightweight status check designed to run on a recurring interval via `/loop`.
Reports only what changed since last check — no noise when things are stable.

## Usage

```
/loop 5m /babysit          → Check every 5 minutes (recommended)
/loop 10m /babysit         → Check every 10 minutes (relaxed)
/babysit                   → One-shot check
```

## Composable flags

Before processing $ARGUMENTS, parse composable flags per `.claude/docs/composable-flags.md`.
Strip recognized flags (--readonly, --concise, --lean, --seq, --local and their short forms)
from $ARGUMENTS before treating the remainder as this command's input.

Apply active flags throughout:
- --readonly: skip all file writes and write-capable agent spawns
- --concise: limit output to 20 lines max
- --lean: use haiku for subagents, minimize tool calls
- --seq: execute agents sequentially, not in parallel
- --local: route eligible subtasks to Ollama, fall back to haiku if unavailable

## What to do

Run these checks quickly and report ONLY items that need attention.

### 1. Agent health
Run `bash scripts/hartz-land/monitor.sh --json 2>/dev/null` if available.
Otherwise check for running Ralph processes:
```bash
ps aux | grep -E 'ralph\.sh|claude' | grep -v grep | head -5
```
Report:
- Number of active agents
- Any agents that appear stuck (no log output in >15 minutes)

### 2. Story progress
Check `scripts/ralph-moss/prds/*/prd.json` for active PRDs.
Compare completed story count. Report:
- Stories completed since session start
- Current story in progress (if identifiable from git branch)
- Any stories marked as stuck

### 3. Review queue
Run `bash scripts/hartz-land/review-queue.sh list --json 2>/dev/null` if available.
Otherwise check `~/.hartz-claude-framework/review-queue/` for pending items.
Report:
- Number of items pending review
- Any high-confidence items (>=0.9) ready for auto-approve
- Flag if queue is growing faster than reviews

### 4. CI / PR status
Run `gh pr list --state open --json number,title,statusCheckRollup --limit 5 2>/dev/null`.
Report:
- Open PRs with failing checks (action needed)
- Open PRs with passing checks (ready to merge)
- Skip PRs with pending checks (nothing to do yet)

### 5. Git conflicts
Run `git status` on the main branch. Report:
- Merge conflicts that need resolution
- Diverged branches that may cause issues

## Output format

Use a compact format. Suppress sections with nothing to report.

```
══════════════════════════════════════
BABYSIT — [time] — [project name]
══════════════════════════════════════

✓ Agents: 2 active, 0 stuck
✓ Progress: 3/8 stories (was 2/8)
  → Working on: US-004 "Add error handling"

⚠ Review queue: 2 pending
  → US-002 (confidence: 0.92) — auto-approve candidate
  → US-003 (confidence: 0.78) — needs human review

⚠ PRs: 1 failing checks
  → #42 "feat: add login flow" — lint failure

✓ No conflicts
```

### Signal levels
- `✓` — healthy, no action needed
- `⚠` — attention recommended (review queue items, failing CI)
- `✗` — action required (stuck agents, merge conflicts, blocked stories)

### Quiet mode
When everything is healthy, output a single line:
```
BABYSIT [time] — All clear. 2 agents active, 3/8 stories done.
```

## Why this exists

`/status` is a comprehensive briefing meant for session starts. `/babysit` is a
lightweight pulse check designed to run on repeat via `/loop` without flooding
your session with noise. It reports by exception — only what changed or needs
attention.
