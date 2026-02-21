# Ralph Loop — Agent Prompt
# Example: Dark Mode Feature

## Project context

You are working on ExampleProject, a React/TypeScript/Supabase application.

Key files to be aware of:
- `src/lib/supabase.ts` — Supabase client (always use this, never import directly)
- `src/contexts/` — React contexts including AuthContext and ThemeContext
- `src/pages/Settings.tsx` — The settings page you'll be modifying
- `supabase/migrations/` — Add new migration files here

## Code style

- Functional React components with named exports
- TypeScript strict mode — no `any` without justification comment
- Tailwind CSS for styling
- Vitest + React Testing Library for tests

## Commands you'll need

```bash
# Generate Supabase types after migrations
npx supabase gen types typescript --local > src/types/database.types.ts

# Run tests
npx vitest run

# Type check
npx tsc --noEmit

# Quality gate (run before every commit)
bash scripts/quality-gate.sh
```

## Important patterns

- Always read `docs/solutions/` for Supabase patterns before writing queries
- RLS policies must be tested with two user accounts
- Theme preference should default to 'system' (respects OS setting)
