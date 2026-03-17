# /review — Parallel Code Review

Spawns specialist review agents in parallel. Each agent reviews independently,
then findings are synthesised into a single P1/P2/P3 report.

## Usage

```
/review                    → Smart-filtered review (agents matched to changed files)
/review --full             → Full review (all agents, no filtering)
/review security           → Security-only review
/review typescript         → TypeScript-only review
/review [scope]            → Review specific file or directory
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

## What happens

### Phase 1: Spec compliance + Blast radius (runs FIRST)
1. Read PROGRESS.md and recent git diff to understand what changed
2. Run `bash scripts/blast-radius.sh --json` to compute the blast radius of the changes
3. Spawn `spec-compliance-reviewer` to verify the implementation matches requirements
4. Wait for spec compliance and blast-radius results before proceeding

### Phase 1a: Blast radius context

The blast-radius JSON output provides:
- `symbols`: list of changed function/class names
- `affected_files`: files that transitively depend on changed symbols, with depth and linkage
- `affected_file_count`: total number of transitively affected files

Use this data to:
- **Feed `architecture-strategist`**: include the affected file list in its prompt so it can assess whether the change respects module boundaries
- **Flag high blast radius**: if `affected_file_count > 20`, add a P2 finding: "HIGH BLAST RADIUS — consider splitting this change"
- **Enrich other agents**: include the blast-radius summary in each agent's context so they know which files are indirectly affected

If `blast-radius.sh` is not found or fails, skip this step and note it in the output.

### Phase 2: Quality review (parallel)
5. Check docs/solutions/ for related past issues (learnings-researcher step)
6. Determine which quality agents are relevant based on the changes
7. Spawn all relevant quality agents in ONE message (parallel execution) — include blast-radius context in each agent's prompt
8. Each agent reviews independently and reports findings

### Phase 3: Synthesis
9. Synthesise all findings (spec + quality + blast radius) into a single report
10. Present consolidated P1/P2/P3 list with agent attribution

## Agent selection logic — Smart filtering

Before spawning Phase 2 agents, determine which files changed and skip irrelevant agents.

### Step 0: Detect changed files

Run `git diff --name-only $(git merge-base HEAD main 2>/dev/null || echo HEAD~1)..HEAD` to get the list of changed files. If that fails, fall back to `git diff --name-only HEAD~1`.

### File category detection

Classify each changed file into one or more categories:

| Category | Glob patterns |
|----------|---------------|
| UI | `**/*.tsx`, `**/*.jsx`, `**/*.vue`, `**/*.svelte`, `**/*.css`, `**/*.scss`, `**/components/**`, `**/pages/**`, `**/layouts/**`, `**/views/**` |
| DB | `**/migrations/**`, `**/db/**`, `**/schema/**`, `**/seeds/**`, `**/models/**`, `**/*.sql`, `**/supabase/**` |
| API | `**/api/**`, `**/routes/**`, `**/controllers/**`, `**/handlers/**`, `**/edge-functions/**` |
| Test | `**/*.test.*`, `**/*.spec.*`, `**/tests/**`, `**/__tests__/**` |
| TypeScript | `**/*.ts`, `**/*.tsx` |
| Docs | `**/*.md`, `**/docs/**` |

### Agent-to-category mapping

| Agent | Runs when | Skip when |
|-------|-----------|-----------|
| `spec-compliance-reviewer` | ALWAYS (Phase 1) | Never skip |
| `security-sentinel` | ANY code file changed | Only docs/config changes |
| `typescript-reviewer` | TypeScript category has matches | No .ts/.tsx files changed |
| `architecture-strategist` | 3+ files changed OR API/DB categories hit | Single-file cosmetic change |
| `error-handling-reviewer` | API or UI category has matches | Only docs/config/test changes |
| `performance-oracle` | DB or API category has matches | No DB or API files changed |
| `data-integrity-guardian` | DB category has matches | No DB files changed |
| `accessibility-reviewer` | UI category has matches | No UI files changed |
| `test-quality-reviewer` | Test category has matches OR new implementation files without corresponding tests | Only docs/config changes |

### Filtering procedure

1. Run git diff to get the changed file list
2. Classify each file into categories using the patterns above
3. For each agent, check if its required categories have matches
4. Log which agents are INCLUDED and which are SKIPPED:

```
Agent filtering (12 files changed):
  ✓ spec-compliance-reviewer — ALWAYS
  ✓ security-sentinel — API files changed (src/api/auth.ts)
  ✓ typescript-reviewer — .ts files changed
  ✗ accessibility-reviewer — SKIPPED (no UI files)
  ✗ data-integrity-guardian — SKIPPED (no DB files)
  ✓ architecture-strategist — 12 files changed (>3 threshold)
  ✓ error-handling-reviewer — API files changed
  ✗ performance-oracle — SKIPPED (no DB/API-heavy files)
  ✓ test-quality-reviewer — test files changed
```

5. Spawn only non-skipped agents (still in ONE message for parallelism, unless --seq)

### Override: --full

If the user passes `--full`, skip all filtering and spawn every agent.
Useful for pre-release reviews or when you want maximum coverage regardless of file categories.

## Agent verdict footer (REQUIRED)

Every review agent MUST end its output with a structured verdict footer:

```
VERDICT: APPROVE | REQUEST_CHANGES | ABSTAIN
REASON: <one-line justification>
```

### Verdict rules
- **APPROVE**: No P1 findings AND 2 or fewer P2 findings
- **REQUEST_CHANGES**: Any P1 finding OR 3+ P2 findings
- **ABSTAIN**: Agent cannot meaningfully evaluate (e.g., accessibility reviewer on backend-only changes)

Agents MUST follow these rules mechanically. Do not APPROVE when P1s exist.

### Phase 3a: Consensus calculation

After collecting all agent verdicts (Phase 2) and before synthesis (Phase 3):

1. Extract each agent's VERDICT line from its output
2. Build a JSON payload:
   ```json
   {
     "threshold": 75,
     "agents": [
       {"name": "security-sentinel", "verdict": "APPROVE", "p1_count": 0},
       {"name": "typescript-reviewer", "verdict": "REQUEST_CHANGES", "p1_count": 2}
     ]
   }
   ```
3. Run `bash scripts/consensus-gate.sh --json <payload-file>`
4. Include the consensus result in the consolidated output (see CONSENSUS section below)

If `consensus-gate.sh` is not found, skip consensus calculation and note it in the output.

## Parallelism rule

Phase 2 quality agents spawn in ONE message. Never spawn sequentially.

```
# Phase 1 — spec compliance first
spawn spec-compliance-reviewer → wait for results

# Phase 2 — all quality agents in one message
[spawn security-sentinel, spawn typescript-reviewer, spawn architecture-strategist]

# Wrong — sequential spawning wastes time
spawn security-sentinel → wait → spawn typescript-reviewer → wait
```

## Learnings integration

Before finalising the review, run a learnings check:
- Search docs/solutions/ for entries tagged with the same files, components, or error types
- Surface any relevant past issues at the bottom of the report
- Flag if a P2/P3 finding matches a previously documented pattern that escalated

## Consolidated output format

```
═══════════════════════════════════════
CODE REVIEW REPORT — [scope] — [date]
═══════════════════════════════════════

P1 — CRITICAL (must fix before merge)
──────────────────────────────────────
[ ] [Issue] (security-sentinel) — auth/login.ts:42
    Risk: Attacker can bypass auth by manipulating token
    Fix: Validate JWT server-side in middleware, not client

[ ] [Issue] (data-integrity-guardian) — migrations/003.sql:15
    Risk: Migration drops NOT NULL constraint, data loss possible
    Fix: Add DEFAULT value before removing NOT NULL

P2 — IMPORTANT (should fix, can be follow-up task)
──────────────────────────────────────────────────
[ ] [Issue] (typescript-reviewer) — components/PipelineView.tsx:88
[ ] [Issue] (performance-oracle) — hooks/useListings.ts:34

P3 — MINOR
──────────
[ ] [Issue] (architecture-strategist) — lib/supabase.ts

QUALITY SCORE
─────────────
Correctness:     0.90
Type safety:     0.75  ← below threshold
Security:        0.85
Performance:     0.80
Data integrity:  0.95
Accessibility:   0.70  ← below threshold
Maintainability: 0.85
Error handling:  0.80

Overall: 0.83 — NEEDS WORK (threshold: 0.85)

CONSENSUS
─────────
Threshold: 75%
  ✓ security-sentinel — APPROVE (0 P1s)
  ✗ typescript-reviewer — REQUEST_CHANGES (2 P1s)
  ✓ architecture-strategist — APPROVE (0 P1s)
  – accessibility-reviewer — ABSTAIN
Consensus: 66% (2/3) — BLOCKED (below 75% threshold)

BLAST RADIUS
────────────
Changed symbols: 19
Affected files:  6 (depth 2) — LOW
  scripts/tests/test-ralph-backoff.sh      via backoff_sleep (test)
  scripts/tests/test-ralph-continuation.sh via build_continuation_prompt (test)
  scripts/tests/test-ralph-hooks.sh        via run_hook (test)

LEARNINGS CHECK
───────────────
Related past issue: docs/solutions/2025-03-rls-user-isolation.md
→ This pattern has caused auth bypass before — review carefully
```

## After review

- P1 items: create tasks immediately, block merge
- P2 items: create follow-up tasks, can merge with plan
- P3 items: log in PROGRESS.md for next session
- Run `/compound` after fixing P1/P2 items to capture learnings
