# /review — Parallel Code Review

Spawns specialist review agents in parallel. Each agent reviews independently,
then findings are synthesised into a single P1/P2/P3 report.

## Usage

```
/review                    → Full review (all relevant agents)
/review security           → Security-only review
/review typescript         → TypeScript-only review
/review [scope]            → Review specific file or directory
```

## What happens

### Phase 1: Spec compliance (runs FIRST)
1. Read PROGRESS.md and recent git diff to understand what changed
2. Spawn `spec-compliance-reviewer` to verify the implementation matches requirements
3. Wait for spec compliance results before proceeding

### Phase 2: Quality review (parallel)
4. Check docs/solutions/ for related past issues (learnings-researcher step)
5. Determine which quality agents are relevant based on the changes
6. Spawn all relevant quality agents in ONE message (parallel execution)
7. Each agent reviews independently and reports findings

### Phase 3: Synthesis
8. Synthesise all findings (spec + quality) into a single report
9. Present consolidated P1/P2/P3 list with agent attribution

## Agent selection logic

**Always spawn first (Phase 1):**
- `spec-compliance-reviewer` — verifies what was built matches what was asked for

**Always spawn (Phase 2):**
- `security-sentinel` — any code that touches auth, data, or user input
- `typescript-reviewer` — any TypeScript changes
- `architecture-strategist` — any structural or module-level changes

**Spawn when relevant (Phase 2):**
- `performance-oracle` — data-heavy features, list views, database queries
- `data-integrity-guardian` — migrations, schema changes, RLS policies
- `accessibility-reviewer` — UI component changes

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
