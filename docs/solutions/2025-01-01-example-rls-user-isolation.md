---
title: "Example: Supabase RLS user isolation pattern"
category: pattern
tags: [supabase, rls, auth, security]
date: 2025-01-01
severity: p1
files_affected:
  - supabase/migrations/
  - src/lib/supabase.ts
---

## Problem

Users were able to see each other's data in the listings table. The Supabase RLS
policy existed but wasn't being enforced correctly because the policy used
`auth.uid()` on a column that stored user IDs as text, while `auth.uid()` returns UUID.

## Root cause

Type mismatch between `auth.uid()` (returns `uuid`) and the `user_id` column
(stored as `text`). PostgreSQL's strict type checking meant the comparison
`user_id = auth.uid()` always evaluated to false, so RLS silently allowed all access.

## Solution

```sql
-- Before (broken — type mismatch)
CREATE POLICY "Users can only see own listings"
ON listings FOR SELECT
USING (user_id = auth.uid());

-- After (fixed — explicit cast)
CREATE POLICY "Users can only see own listings"
ON listings FOR SELECT
USING (user_id = auth.uid()::text);

-- Or better — change column type to uuid
ALTER TABLE listings ALTER COLUMN user_id TYPE uuid USING user_id::uuid;
```

## Prevention

- Always check column types when writing RLS policies
- Test RLS with two different user accounts — not just your own
- Add a test case: `expect(otherUserData).toBeNull()` after auth switch
- Prefer storing user IDs as `uuid` type to match `auth.uid()` return type

## Related

- Supabase RLS documentation: https://supabase.com/docs/guides/database/row-level-security
