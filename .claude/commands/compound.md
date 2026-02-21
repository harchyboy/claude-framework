# /compound — Capture Learnings

After fixing bugs or solving non-obvious problems, run `/compound` to extract institutional
knowledge into `docs/solutions/`. This builds the project's searchable knowledge base.

Inspired by Every Inc's Compound Engineering philosophy: make every unit of work compound
into the next.

## When to run

- After fixing any P1 or P2 review finding
- After solving a bug that took >2 attempts
- After discovering a non-obvious Supabase/TypeScript pattern
- After resolving a migration or data integrity issue
- After a security finding is remediated

## What happens

Six sub-agents extract knowledge from the recent work (spawned in ONE message):

1. **Context analyser** — what was the context and what changed?
2. **Solution extractor** — what specifically fixed it?
3. **Related docs finder** — are there existing solution docs to update rather than duplicate?
4. **Prevention strategist** — what would have prevented this?
5. **Category classifier** — bug-fix / pattern / workaround / architecture-decision
6. **Documentation writer** — synthesises into the final YAML-frontmatter doc

## Output

Creates `docs/solutions/YYYY-MM-DD-[slug].md`:

```yaml
---
title: "Brief description of the solution"
category: bug-fix
tags: [supabase, rls, auth, typescript]
date: 2025-03-15
severity: p1
files_affected:
  - src/lib/supabase.ts
  - supabase/migrations/004_fix_rls.sql
---

## Problem
What went wrong and how it manifested in the application.

## Root cause
Why it happened — the underlying mechanism, not just the symptom.

## Solution
```typescript
// Before (broken)
const { data } = await supabase.from('listings').select('*')

// After (fixed)
const { data } = await supabase
  .from('listings')
  .select('*')
  .eq('owner_id', user.id)  // RLS wasn't catching this case
```

## Prevention
- Always test RLS policies with a second user account
- Add `eq('owner_id', user.id)` as explicit filter even when RLS should handle it
- Check docs/solutions/ before implementing auth patterns

## Related
- docs/solutions/2025-02-rls-basics.md
```

## Integration with /review

When `/review` runs, it automatically:
- Searches `docs/solutions/` for entries tagged with the same files
- Surfaces relevant past issues in the LEARNINGS CHECK section
- Flags when current findings match documented patterns

This is the closed feedback loop: bugs become documented patterns, workarounds become
official approaches, and every developer (human or AI) benefits from accumulated knowledge.
