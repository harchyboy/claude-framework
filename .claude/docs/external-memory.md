# External Memory Protocol

Every agent, every session, follows this protocol:

## Before starting work
1. Read `PROGRESS.md` — understand current state and what's already been tried
2. Search `docs/solutions/` for patterns relevant to your task
3. Check `docs/failed-approaches.md` — never retry a known failure
4. Check `current_tasks/` — do NOT claim a task already locked

## After completing work
1. Update `PROGRESS.md` with: what changed, what's next, any blockers
2. If you solved a non-obvious problem, create a `docs/solutions/YYYY-MM-DD-slug.md` entry
3. If something didn't work after 3 attempts, add to `docs/failed-approaches.md`
4. Remove your lock file from `current_tasks/` after committing

## Learnings file format (`docs/solutions/YYYY-MM-DD-slug.md`)
```yaml
---
title: "Brief description of the solution"
category: bug-fix | pattern | workaround | architecture-decision
tags: [supabase, auth, typescript, react, rls]
date: YYYY-MM-DD
severity: p1 | p2 | p3
---

## Problem
What went wrong and how it manifested.

## Root cause
Why it happened.

## Solution
What fixed it, with code snippets.

## Prevention
How to avoid this class of problem in the future.
```

## Failed approaches format (`docs/failed-approaches.md`)
```markdown
### YYYY-MM-DD — [Brief description]

**What was tried:** Describe the approach.
**Why it failed:** Root cause or error.
**What to do instead:** The working alternative.
```
