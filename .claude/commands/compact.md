---
name: compact
description: Strategic context compaction — saves state before compacting at a logical boundary
---

# Strategic Compaction

You are being asked to perform a strategic compaction. This is better than auto-compaction because it happens at a logical boundary in the work.

## Step 1 — Assess Current State

Before compacting, capture the current state:

1. What task are you currently working on?
2. What phase are you in? (research / planning / implementing / testing / reviewing)
3. What decisions have been made?
4. What's left to do?

## Step 2 — Write Recovery Context

Write a concise recovery context to `.claude/handoff/session-summary.md`:

```markdown
# Session State — [timestamp]

Branch: [current branch]

## Current Task
[What you're working on, with specific details]

## Phase
[research | planning | implementing | testing | reviewing]

## Completed This Session
- [Specific items completed]

## Key Decisions
- [Belief statements, not history: "Auth uses Bearer tokens" not "we discussed auth options"]

## In Progress
- [What's partially done, with current state]

## Next Steps
- [Ordered list of what to do next]

## Files Modified
[List of files changed]
```

## Step 3 — Compact

After writing the recovery context, use `/compact` to compress the conversation.

## Step 4 — Verify Recovery

After compaction, read `.claude/handoff/session-summary.md` and confirm you have full context to continue.

## When to Use This

Use `/compact` at these natural boundaries:
- After completing a research phase, before starting implementation
- After finishing a set of related file changes
- After debugging is resolved, before moving to the next issue
- When you notice response quality degrading
- After ~50 tool calls in a session
- Before switching to a different area of the codebase

**Never** compact mid-implementation or mid-debugging — finish the logical unit first.
