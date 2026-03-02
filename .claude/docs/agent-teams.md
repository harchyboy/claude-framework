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
