---
title: "Build-vs-buy decision framework for external tools"
category: architecture-decision
tags: [architecture, dependencies, build-vs-buy, evaluation]
date: 2026-03-17
severity: p3
files_affected:
  - scripts/blast-radius.sh
---

## Problem

Evaluating external tools for integration is often done by one person reading
the README. This misses maturity signals, environmental incompatibilities, and
the actual surface area of value needed.

## Root cause

Tool evaluation bias: the first solution that looks promising gets integrated
without adversarial analysis of its fitness for the specific runtime environment,
dependency footprint, and maintenance trajectory.

## Solution

### The Four-Analyst Pattern

Spin up four parallel evaluation agents, each with a distinct adversarial lens:

| Analyst | Question |
|---------|----------|
| **Token/Cost Analyst** | What does this actually cost? API calls, context size, latency? |
| **Architect** | Does it integrate cleanly? Worktrees, CI, shell environment? |
| **Quality Analyst** | How mature? Changelog red flags, open critical bugs, contributor count? |
| **Skeptic** | What's the minimum subset we need? Can we build that in <500 lines? |

### Decision Rubric

Score each factor 1 (bad) to 3 (good). Require >= 10/12 to integrate.

| Factor | 1 (red) | 2 (yellow) | 3 (green) |
|--------|---------|------------|-----------|
| Project age | < 30 days or critical bugs | < 6 months, no critical bugs | > 6 months, maintained |
| Environmental fit | Hard blocker | Requires workaround | Drop-in |
| Dependency footprint | > 10 transitive deps | 2-10 deps | 0-1 deps / stdlib |
| Value capture ratio | Need < 30% of features | Need 30-70% | Need > 70% |

### Case Study — `tirth8205/code-review-graph`

```
Project age:        19 days, critical bugs in changelog   → 1
Environmental fit:  worktree incompatibility (blocker)    → 1
Dependency footprint: Python + pip deps                   → 2
Value capture ratio: ~20% of features needed              → 1

Total: 5/12  →  DO NOT INTEGRATE
```

Decision: extract the core concept (blast-radius / call-graph tracing) and
implement in ~300 lines of bash. Result: `scripts/blast-radius.sh` — zero
dependencies, works in worktrees, deployed to 10 projects in one command.

### When to build

- Score < 10/12
- Valuable subset is < 500 lines in your scripting language
- Tool has a hard runtime blocker (worktrees, no Windows, requires Docker)
- Project is < 30 days old with known critical bugs

### When to buy

- Score >= 10/12
- Tool solves a genuinely hard problem (crypto, auth, parsing)
- Maintained by reputable org with SLA/LTS
- Integration is additive (optional, not on critical path)

## Prevention

- Run four-analyst evaluation before merging any PR that adds a runtime dependency
- Document rejected tools in `docs/failed-approaches.md` with score so future
  agents don't re-evaluate
- Re-evaluate tools that scored 8-9 after 90 days — projects mature quickly

## Related

- `.claude/docs/agent-teams.md` — debate pattern (four-analyst)
- `docs/failed-approaches.md` — rejected tool entries
- `CLAUDE.md` — model routing table (Opus for architecture decisions)
