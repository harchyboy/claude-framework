# Quality Gates

## Pre-commit (run before every commit)
```bash
bash scripts/quality-gate.sh
```
Checks: TypeScript compile → ESLint → Tests → No secrets in diff

## Code review — two-phase process

**Phase 1: Spec compliance** (runs first, blocks Phase 2 on failure)
- `spec-compliance-reviewer` — verifies implementation matches requirements/PRD/acceptance criteria

**Phase 2: Quality review** (9 agents, run in parallel)

## Code review scoring (9 dimensions, threshold: 0.85)
When evaluating completed work, score these dimensions 0.0–1.0.
**Review against `docs/CODE-STANDARDS.md`** — violations of documented standards are automatic P1s.

| Dimension | What to check |
|-----------|---------------|
| Correctness | Works as specified, handles edge cases |
| Test quality | Edge cases covered, adequate coverage |
| Type safety | No `any`, proper generics, exhaustive type guards (CODE-STANDARDS §2) |
| Security | Auth via headers, input validation, path traversal guards (CODE-STANDARDS §1) |
| Performance | Parallel I/O, no N+1 queries, pagination on unbounded lists (CODE-STANDARDS §7) |
| Error handling | Graceful failures, consistent error contracts, resp.ok checks |
| Accessibility | Label associations, focus management, complete ARIA patterns (CODE-STANDARDS §3) |
| Data integrity | Atomic writes, validation before persistence, lock TTLs (CODE-STANDARDS §4) |
| Maintainability | Clear naming, DRY, single responsibility |

If `overall_score < 0.85`, create a remediation task with specific fix instructions before marking complete.

## Review output format
All review agents report findings in this format:
```
P1 — CRITICAL (must fix before merge):
[ ] Issue description (agent-name) — file.ts:42

P2 — IMPORTANT (should fix, can be follow-up task):
[ ] Issue description (agent-name) — file.ts:42

P3 — MINOR (nice to have):
[ ] Issue description (agent-name) — file.ts:42

LEARNINGS CHECK:
[ ] Related past issue found: docs/solutions/2025-03-auth-bypass.md
```

## Automated hooks

The framework installs these hooks automatically. They run without user action.

| Hook | Trigger | What it does |
|------|---------|-------------|
| `session-start.sh` | SessionStart | Injects PROGRESS.md, failed-approaches, task locks into context |
| `pre-tool-use.sh` | PreToolUse (Write/Edit) | Re-reads PROGRESS.md top 30 lines to prevent goal drift |
| `post-tool-use.sh` | PostToolUse (Edit/Write) | Runs ESLint on changed file for instant feedback |
| `permission-request.sh` | PermissionRequest | Auto-approves safe commands, blocks dangerous ones |
| `subagent-start.sh` | SubagentStart | Injects project state into every spawned subagent |
| `pre-compact.sh` | PreCompact | Snapshots session state before context compaction |
| `check-complete.sh` | Stop | Verifies PROGRESS.md was updated + semantic completion check |
| `task-completed.sh` | TaskCompleted | Runs quality gate; checks PROGRESS.md freshness |
| `teammate-idle.sh` | TeammateIdle | Checks for unclaimed tasks before allowing shutdown |

### Session recovery
After a `/clear` or context compaction, run:
```bash
bash scripts/session-catchup.sh
```
Parses Claude Code's internal session files to recover what happened after the last PROGRESS.md update.
