# Quality Gates

## Pre-commit (run before every commit)
```bash
bash scripts/quality-gate.sh [--strict] [--coverage] [--fix] [--skip-tests]
```
Checks: Secret detection (all staged changes) → TypeScript compile → ESLint → Tests → Coverage thresholds (with `--coverage`)

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

## Consensus Gating

Review agents emit structured verdicts (`APPROVE`, `REQUEST_CHANGES`, `ABSTAIN`).
Consensus gating aggregates these into a single APPROVED/BLOCKED decision.

### Formula
```
consensus% = APPROVE_count / (APPROVE_count + REQUEST_CHANGES_count) × 100
```
- ABSTAIN agents are excluded from the denominator
- If all agents ABSTAIN → BLOCKED
- Default threshold: **75%**

### P1 Veto
Any agent with `p1_count > 0` forces **BLOCKED** regardless of consensus percentage.
This prevents merging code with critical issues even if most agents approve.

### Standalone usage
```bash
# From a JSON file
bash scripts/consensus-gate.sh --json verdicts.json

# From stdin
echo '{"threshold":75,"agents":[...]}' | bash scripts/consensus-gate.sh

# Custom threshold
bash scripts/consensus-gate.sh --threshold 80 --json verdicts.json

# Quiet mode (exit code only)
bash scripts/consensus-gate.sh --quiet --json verdicts.json
```

### JSON format
```json
{
  "threshold": 75,
  "agents": [
    {"name": "security-sentinel", "verdict": "APPROVE", "p1_count": 0},
    {"name": "typescript-reviewer", "verdict": "REQUEST_CHANGES", "p1_count": 1}
  ]
}
```

### Exit codes
- `0` — APPROVED (consensus >= threshold, no P1 vetoes)
- `1` — BLOCKED (below threshold, P1 veto, all abstain, or error)

### Integration with /review
The `/review` command automatically runs consensus gating in Phase 3a (between agent collection and synthesis). See `.claude/commands/review.md`.

### Integration with workflows
Workflow YAML files can specify `quality_gate.consensus_threshold` on any phase. The workflow runner calls `consensus-gate.sh` automatically. See `.claude/docs/workflow-as-code.md`.

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
| `task-completed.sh` | TaskCompleted | Runs quality gate; checks PROGRESS.md freshness |
| `teammate-idle.sh` | TeammateIdle | Checks for unclaimed tasks before allowing shutdown |

### Session recovery
After a `/clear` or context compaction, run:
```bash
bash scripts/session-catchup.sh
```
Parses Claude Code's internal session files to recover what happened after the last PROGRESS.md update.
