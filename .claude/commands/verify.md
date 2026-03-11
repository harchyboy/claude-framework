# /verify — Independent Verification of Completed Work

Verify that completed stories actually work by running an independent verification agent.

## Usage
```
/verify [story-id]          Verify a specific story
/verify --all               Verify all stories marked passes:true that lack proof packets
/verify --recheck [id]      Re-verify a previously verified story
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

## What This Does

1. **Finds the story** from the active PRD
2. **Spawns a verification agent** (separate from the implementor) that:
   - Reads acceptance criteria from the PRD
   - Inspects the code diff and tests
   - Runs the test suite
   - Starts the dev server (if UI story)
   - Uses Playwright to interact with the running app
   - Tries edge cases to break the implementation
3. **Generates a proof packet** in `proof/[story-id]/`:
   - `criteria.md` — Original acceptance criteria
   - `verification.md` — Detailed verification report
   - `verdict.json` — Machine-readable pass/fail with confidence score
   - `screenshots/` — Evidence screenshots
4. **Reports the verdict** with a confidence score

## Verification Workflow

```
┌─────────────────────────────────────────────┐
│  1. Read PRD acceptance criteria            │
│  2. Read code diff + tests                  │
│  3. Run test suite (npm test / vitest)      │
│  4. Start dev server                        │
│  5. Playwright: navigate + verify each      │
│     criterion via accessibility tree        │
│  6. Try edge cases (empty input, etc.)      │
│  7. Take screenshots as evidence            │
│  8. Score confidence 0.0-1.0                │
│  9. Write proof packet                      │
└─────────────────────────────────────────────┘
```

## Implementation

When the user runs `/verify`, do the following:

### Step 1: Find the PRD and story
```
Search scripts/ralph-moss/prds/*/prd.json for the target story.
If --all, find all stories where passes:true but no proof/[story-id]/verdict.json exists.
```

### Step 2: Spawn the verification agent
Use the Agent tool to spawn a `general-purpose` agent with the verification-agent persona:

```
Read .claude/agents/verification-agent.md for the full agent instructions.
Pass it:
- The acceptance criteria for the story
- The files that were changed (from git log or filesInScope)
- The dev server start command (from package.json scripts)
```

### Step 3: Collect and display results
After the agent completes:
- Read `proof/[story-id]/verdict.json`
- Display summary to user:
  - Per-criterion pass/fail
  - Overall verdict and confidence
  - Any issues found
  - Screenshot paths

### Step 4: Update review queue
If confidence >= 0.9: suggest auto-merge
If confidence 0.7-0.89: add to review queue
If confidence < 0.7: flag for immediate attention

## Confidence Thresholds

| Score | Meaning | Action |
|-------|---------|--------|
| 0.9+ | High confidence — all criteria verified | Auto-merge candidate |
| 0.7-0.89 | Medium — mostly verified, minor gaps | Queue for human review |
| < 0.7 | Low — failures or insufficient evidence | Block, needs fixing |
