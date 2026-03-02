# /status — Project Status Briefing

Quick overview of the project's current state. Use when starting a session,
returning after time away, or checking progress mid-work.

## What to do

Generate a status briefing by reading these sources in order:

### 1. PROGRESS.md
Read the full `PROGRESS.md`. Report:
- What was last worked on
- Current blockers
- Next priorities
- When it was last updated

### 2. Recent git activity
Run `git log --oneline -15` and `git branch --show-current`. Report:
- Current branch name
- Last 10 commit messages with dates
- Any uncommitted changes (`git status`)

### 3. Active PRDs
Check `scripts/ralph-moss/prds/*/prd.json` for PRDs with incomplete stories.
For each active PRD, report:
- PRD name and description
- Stories completed vs total
- Next pending story (highest priority with `passes: false`)

### 4. Task locks
Check `current_tasks/` for active lock files. Report:
- Which tasks are locked and by whom
- Whether any locks look stale (older than 2 hours based on git log)

### 5. Failed approaches
Read headings from `docs/failed-approaches.md` (last 5 entries). Report:
- Recent things that didn't work (so you don't retry them)

### 6. Recent learnings
List titles from `docs/solutions/` (last 5 files by date). Report:
- Recent solutions that might be relevant

## Output format

```
═══════════════════════════════════════
PROJECT STATUS — [project name] — [date]
═══════════════════════════════════════

BRANCH: [current branch]
LAST UPDATED: [PROGRESS.md timestamp]

RECENT ACTIVITY (last 10 commits)
─────────────────────────────────
  abc1234 feat: add login flow
  def5678 fix: auth token refresh
  ...

ACTIVE PRDs
───────────
  [prd-name]: 3/5 stories complete
  → Next: US-004 "Add error handling to login"

TASK LOCKS
──────────
  [none] or [task-name: locked by agent-x, 45 min ago]

BLOCKERS
────────
  [from PROGRESS.md or "None"]

NEXT PRIORITIES
───────────────
  1. [from PROGRESS.md]
  2. [from PROGRESS.md]

RECENT LEARNINGS
────────────────
  - 2025-03-15: RLS user isolation pattern
  - 2025-03-10: Auth token refresh fix

FAILED APPROACHES (don't retry)
───────────────────────────────
  - JWT client-side validation
  - Direct PostgREST access
```
