# Agent Teams — Orchestration Patterns

## Leader pattern (feature development)
```
Orchestrator (Opus, delegate mode ON)
├── frontend-agent   → owns src/components/, src/pages/
├── backend-agent    → owns src/api/, src/lib/
└── test-agent       → owns src/__tests__/, e2e/
```
Workers never touch each other's directories. Findings shared via write().

## Swarm pattern (code review)
Spawn all review agents simultaneously in ONE message:
```
security-sentinel + typescript-reviewer + architecture-strategist
+ performance-oracle + data-integrity-guardian + accessibility-reviewer
```
Each claims independent review tasks. Lead synthesises findings into P1/P2/P3 report.

## Debate pattern (debugging / architecture)
Spawn 3 agents, each with a different root-cause hypothesis. Have them challenge
each other's conclusions via broadcast(). Lead picks the strongest argument.

## Watchdog pattern (risky refactors)
Spawn implementation agent with `planModeRequired: true`.
Spawn watchdog agent to monitor changes and flag scope creep.
Lead approves plans before any file writes.

## Wave decomposition (large features)
```
Wave 1 (parallel): types, schemas, utility functions — no shared state
Wave 2 (parallel): components, API routes, DB functions — file ownership assigned
Wave 3 (parallel): integration, wiring state to API — depends on Wave 2
Wave 4 (parallel): unit tests, integration tests — depends on Wave 3
Wave 5 (sequential): review, documentation, cleanup
```
Each wave's tasks run in parallel. Waves execute sequentially.

## Iterative retrieval pattern (subagent accuracy)

When a subagent returns results, don't blindly accept — evaluate and iterate:

```
Cycle 1: Orchestrator sends query + objective context to subagent
         Subagent returns initial findings
         Orchestrator evaluates: sufficient? accurate? complete?

Cycle 2: If insufficient, orchestrator sends follow-up with:
         - What was missing from the first response
         - Additional context the subagent needs
         - Specific files or areas to investigate
         Subagent returns refined findings

Cycle 3: Final iteration if needed (max 3 cycles)
         After 3 cycles, accept best result or escalate
```

Key principles:
- **Pass objective context, not just queries.** Subagent only knows the literal query,
  not WHY you need the information. Include the purpose.
- **Max 3 cycles.** If 3 rounds don't produce sufficient results, the query is wrong
  or the task needs a different approach.
- **Each cycle narrows scope.** Don't repeat the same query — refine it based on what
  the previous response revealed.

Example:
```
# BAD — subagent has no context
Agent: "Find all API routes"

# GOOD — subagent understands the objective
Agent: "Find all API routes that handle user authentication.
        I need this to audit auth middleware coverage.
        Focus on routes in src/api/ that accept credentials
        or return tokens."
```

## Sequential phase pattern (large features)

For complex tasks, chain agents through explicit phases with file-based handoffs:

```
Phase 1: RESEARCH    → .claude/handoff/research-summary.md
Phase 2: PLAN        → .claude/handoff/plan.md
Phase 3: IMPLEMENT   → code changes (committed)
Phase 4: REVIEW      → .claude/handoff/review-comments.md
Phase 5: VERIFY      → done or loop back to Phase 3
```

Each agent gets ONE clear input file and produces ONE clear output file.
Outputs become inputs for the next phase. This eliminates context ambiguity
and allows different models per phase (Haiku for research, Sonnet for implement).

---

## Self-organising Worker Preamble

When spawning teammates in an Agent Team, give each this preamble (replace placeholders):

```
You are [AGENT_NAME] on team [TEAM_NAME].
Your specialisation: [ROLE_DESCRIPTION]
Your file ownership: [DIRECTORY_OR_FILE_LIST]

Work loop:
1. Check task list for pending, unowned tasks matching your role
2. If found:
   - Claim: TaskUpdate({ taskId: "X", owner: "[AGENT_NAME]" })
   - Start: TaskUpdate({ taskId: "X", status: "in_progress" })
   - Execute the work
   - Complete: TaskUpdate({ taskId: "X", status: "completed" })
   - Report findings to team-lead via Teammate write()
   - Return to step 1
3. If no tasks available:
   - Notify team-lead you are idle via write()
   - Wait 30 seconds and check again (up to 3 times)
   - If still nothing, request shutdown

Rules:
- Read files before editing them
- Run tests after any code changes
- NEVER edit files outside your ownership boundary
- Communicate results via write(), not text output
```
