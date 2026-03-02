# Tech Stack Conventions

> Fill in this section for each project. Defaults shown below for common stacks.
> Delete sections that don't apply to your project.

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

## Testing (Node.js)
- Unit/integration: Vitest + React Testing Library
- E2E: Playwright
- Coverage targets: 80% business logic, 60% UI components
- Test files colocated: `Auth.tsx` → `__tests__/Auth.test.tsx`
- Machine-parseable output: errors prefixed with `ERROR:` for grep

---

## Python
- Type hints on all public functions — `mypy --strict` on core modules
- Use `ruff` for linting and formatting (replaces flake8/black/isort)
- Package management: `uv` (preferred), `poetry`, or `pip` with `requirements.txt`
- Project config in `pyproject.toml` — avoid `setup.py` for new projects

## Python frameworks
- **FastAPI**: async by default, Pydantic models for request/response validation
- **Django**: use class-based views, Django REST Framework for APIs
- **Flask**: blueprints for route organization, app factory pattern

## Testing (Python)
- Unit/integration: `pytest` with `pytest-cov` for coverage
- Fixtures over setup/teardown — use `conftest.py` for shared fixtures
- Test files colocated: `auth.py` → `tests/test_auth.py`
- Coverage targets: 80% business logic, 60% API routes
- Async tests: `pytest-asyncio` for FastAPI/async code

## Git conventions
- Branch: `feature/US-001-brief-description` or `fix/bug-description`
- Commits: conventional commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`)
- PR size: max 400 lines — decompose larger changes
- Never force-push to `main`
