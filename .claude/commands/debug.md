# /debug — Bug Investigation (Debate or Systematic)

Two modes: **debate** (default) spawns 3 hypothesis agents in parallel for complex bugs.
**Systematic** follows a 4-phase root-cause process for everyday bugs.

## Usage

```
/debug The login page shows a blank screen after successful authentication
/debug --systematic API returns 500 on POST /api/bookings with valid data
/debug Dashboard metrics show incorrect totals after timezone change
```

**Mode selection:**
- `--systematic` (or `--sys`): 4-phase root-cause investigation (single-threaded, methodical)
- Default (no flag): debate pattern with 3 parallel hypothesis agents

**When to use which:**
- **Systematic**: everyday bugs, test failures, build errors, "just broke after a change"
- **Debate**: complex bugs with multiple possible causes, intermittent failures, cross-system issues

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

---

## Systematic Mode (`--systematic`)

When `--systematic` or `--sys` flag is present, use this 4-phase root-cause process
instead of the debate pattern. No subagents — you investigate directly.

### The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you haven't completed Phase 1, you cannot propose fixes.

### Phase 1: Root Cause Investigation

**BEFORE attempting ANY fix:**

1. **Read error messages carefully** — don't skip past errors. Read stack traces completely.
   Note line numbers, file paths, error codes. They often contain the exact solution.

2. **Reproduce consistently** — Can you trigger it reliably? What are the exact steps?
   If not reproducible, gather more data. Do NOT guess.

3. **Check recent changes** — `git log --oneline -10`, `git diff`. What changed that
   could cause this? New dependencies, config changes, environmental differences?

4. **Gather evidence at component boundaries** — For multi-component systems, add
   diagnostic logging at each boundary BEFORE proposing fixes:
   ```
   For EACH component boundary:
     - Log what data enters the component
     - Log what data exits the component
     - Verify environment/config propagation
   Run once. Read evidence. THEN identify failing component.
   ```

5. **Trace data flow** — Where does the bad value originate? What called this with
   the bad value? Keep tracing backward until you find the source. Fix at source,
   not at symptom.

### Phase 2: Pattern Analysis

1. **Find working examples** — locate similar working code in the same codebase.
2. **Compare against references** — if implementing a pattern, read the reference
   implementation COMPLETELY. Don't skim.
3. **Identify differences** — list every difference between working and broken,
   however small. Don't assume "that can't matter."

### Phase 3: Hypothesis and Testing

1. **Form a single hypothesis** — "I think X is the root cause because Y." Be specific.
2. **Test minimally** — make the SMALLEST possible change. One variable at a time.
3. **Verify** — Did it work? Yes → Phase 4. No → form NEW hypothesis.
   Do NOT add more fixes on top.
4. **When you don't know** — Say "I don't understand X." Don't pretend.

### Phase 4: Implementation

1. **Create a failing test case** — simplest possible reproduction. MUST have before fixing.
2. **Implement a single fix** — address root cause. ONE change. No "while I'm here" improvements.
3. **Verify the fix** — test passes? No other tests broken? Issue actually resolved?
4. **If fix doesn't work** — count how many fixes you've tried:
   - If < 3: return to Phase 1, re-analyze with new information
   - **If >= 3: STOP. Question the architecture.**

### The 3-Fix Escalation Rule

After 3 failed fixes, this is NOT a failed hypothesis — it's a wrong architecture.

**Signals of architectural problem:**
- Each fix reveals new shared state / coupling / problem in a different place
- Fixes require "massive refactoring" to implement
- Each fix creates new symptoms elsewhere

**Action:** Stop fixing. Discuss with the user. Document in `docs/failed-approaches.md`.

### Red Flags — STOP and return to Phase 1

If you catch yourself thinking:
- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "I don't fully understand but this might work"
- "It's probably X, let me fix that"
- "One more fix attempt" (when already tried 2+)

### Systematic Mode Output Format

```
═══════════════════════════════════════
DEBUG INVESTIGATION (SYSTEMATIC) — [date]
═══════════════════════════════════════

BUG: [description]

PHASE 1 — ROOT CAUSE
─────────────────────
Error: [exact error message / stack trace summary]
Reproduction: [steps to trigger]
Recent changes: [relevant commits]
Evidence: [what diagnostic output showed]

PHASE 2 — PATTERN ANALYSIS
───────────────────────────
Working example: [file:line — what works]
Broken code: [file:line — what's different]
Key difference: [the specific divergence]

PHASE 3 — HYPOTHESIS
─────────────────────
Hypothesis: [specific root cause theory]
Test: [what minimal change was tried]
Result: [confirmed / refuted]

PHASE 4 — FIX
──────────────
Root cause: [confirmed cause]
Fix: [specific change made]
Test: [verification command and output]
Status: DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED
```

### After systematic debug
- Run `/compound` to capture the learnings
- If the bug took >2 attempts, add to `docs/solutions/`
