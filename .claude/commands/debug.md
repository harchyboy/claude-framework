# /debug — Debate-Pattern Bug Investigation

Spawns 3 hypothesis agents in parallel, each investigating a different possible
root cause. Agents challenge each other's findings. Lead synthesises into a
ranked list of causes with evidence.

## Usage

```
/debug The login page shows a blank screen after successful authentication
/debug API returns 500 on POST /api/bookings with valid data
/debug Dashboard metrics show incorrect totals after timezone change
```

## What to do

### Step 1: Gather context
1. Read PROGRESS.md for recent changes
2. Run `git log --oneline -10` to see recent commits
3. Check `docs/failed-approaches.md` for previously attempted fixes
4. Check `docs/solutions/` for related patterns

### Step 2: Formulate 3 hypotheses
Based on the bug description and context, formulate 3 distinct root cause hypotheses.
Each must be:
- **Specific** — not "something is wrong with auth" but "JWT refresh token is expired and the silent refresh fails because the interceptor swallows the 401"
- **Testable** — there's a concrete way to verify or disprove it
- **Different** — each hypothesis should target a different layer or component

### Step 3: Spawn 3 investigation agents
Spawn all 3 in ONE message (parallel execution). Each agent gets:

```
You are Investigator [A/B/C] on a debug team.

BUG: [description]

YOUR HYPOTHESIS: [specific hypothesis]

TASK:
1. Search the codebase for evidence supporting or refuting your hypothesis
2. Look for the specific code paths involved
3. Check git log for recent changes to these files
4. Rate your confidence (HIGH / MEDIUM / LOW) with specific evidence

Report your findings in this format:
  HYPOTHESIS: [your hypothesis]
  CONFIDENCE: [HIGH/MEDIUM/LOW]
  EVIDENCE FOR:
    - [file:line] [what you found]
  EVIDENCE AGAINST:
    - [file:line] [what contradicts your hypothesis]
  VERDICT: [LIKELY ROOT CAUSE / CONTRIBUTING FACTOR / UNLIKELY]
  SUGGESTED FIX: [specific fix if this is the root cause]
```

Use model: **sonnet** for all 3 investigators.
Each investigator gets tools: **Read, Glob, Grep** (read-only).

### Step 4: Synthesise
After all 3 agents report:
1. Compare evidence across hypotheses
2. Identify which hypothesis has the strongest evidence
3. Check if multiple causes are interacting
4. Rank causes by likelihood

### Output format

```
═══════════════════════════════════════
DEBUG INVESTIGATION — [date]
═══════════════════════════════════════

BUG: [description]

RANKED ROOT CAUSES
──────────────────

#1 — [CONFIDENCE: HIGH] [Hypothesis]
     Evidence: [key finding] — file.ts:42
     Fix: [specific remediation]

#2 — [CONFIDENCE: MEDIUM] [Hypothesis]
     Evidence: [key finding] — file.ts:88
     Fix: [specific remediation]

#3 — [CONFIDENCE: LOW] [Hypothesis]
     Evidence: [key finding]
     Fix: [specific remediation]

RECOMMENDED ACTION
──────────────────
Start with cause #1. Apply the fix and test.
If the bug persists, investigate cause #2.

RELATED LEARNINGS
─────────────────
[any relevant docs/solutions/ entries]
```

### Step 5: Act on findings
- If confidence is HIGH: implement the fix immediately
- If confidence is MEDIUM: implement with extra logging to verify
- If all LOW: ask the user for more context or reproduction steps
- Document the fix in `docs/solutions/` via `/compound`
