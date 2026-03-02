# Tech Stack Conventions

> Fill in this section for each project. Defaults shown for React/TypeScript/Supabase.

## TypeScript
- Strict mode — no `any` without a justification comment
- Exhaustive checks on discriminated unions
- Generate Supabase types: `npx supabase gen types typescript`
- All API responses typed — never `unknown` without narrowing

## React
- Functional components only — no class components
- Error boundaries at route level
- Lazy loading for routes: `React.lazy(() => import('./pages/X'))`
- State co-located at lowest necessary level

## Supabase
- All DB access via `src/lib/supabase.ts` — never direct fetch to PostgREST
- RLS policies MANDATORY on all tables — test them
- Edge Functions for server-side logic
- Migrations versioned in `supabase/migrations/`
- Test RLS after any table or policy change

## Testing
- Unit/integration: Vitest + React Testing Library
- E2E: Playwright
- Coverage targets: 80% business logic, 60% UI components
- Test files colocated: `Auth.tsx` → `__tests__/Auth.test.tsx`
- Machine-parseable output: errors prefixed with `ERROR:` for grep

## Git conventions
- Branch: `feature/US-001-brief-description` or `fix/bug-description`
- Commits: conventional commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`)
- PR size: max 400 lines — decompose larger changes
- Never force-push to `main`
