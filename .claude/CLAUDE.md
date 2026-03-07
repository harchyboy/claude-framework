# Hartz Claude Framework — Agent Rules

> Universal engineering rules for all Hartz AI projects. Stack-agnostic.
> Domain-specific rules in .claude/rules/ activate by file path.

## Session Start

- Read .claude/handoff/session-summary.md if it exists before doing anything.
- Read docs/lessons-learned.md if it exists before doing anything.
- Research before implementing. Check if the feature already exists before building it.

## Commit Conventions

- Use conventional commits: `type(scope): description [TICKET-ID]`
- Valid types: feat, fix, test, refactor, docs, chore, style, perf, ci, build
- Always include the ticket ID (e.g., KPF-042, UNION-108).
- Never commit secrets, API keys, or .env files.
- One logical change per commit. Do not bundle unrelated changes.

## Test-First Rule

- Write failing tests BEFORE implementation. No exceptions.
- Run the test suite and confirm tests FAIL (red state) before writing implementation.
- Implement minimum code to make tests pass (green state).
- Run the test suite and confirm ALL tests pass after implementation.
- Never modify tests to make them pass — fix the implementation instead.
- Tests must be isolated: no shared state, no test interdependence, no reliance on execution order.

## Context Management

- At 60K tokens or when reasoning quality degrades, write a handoff file.
- Write handoff to .claude/handoff/session-summary.md using the structured format.
- Use belief statements, not conversation history. Write "Auth uses Bearer tokens" not "I tried basic auth but switched to Bearer."
- Never use /compact. It is opaque and error-prone.
- Start a fresh session after writing the handoff.

## File Ownership

- Only modify files within your assigned scope.
- Backend agents: never touch frontend files (components, styles, layouts).
- Frontend agents: never write database queries or migrations.
- Test agents: never modify implementation source files.
- Implementation agents: never modify test files.

## Branch Strategy

- Branch naming: `[PROJECT]-[TICKET]-[description]` (e.g., kpf-042-oauth-flow)
- Always branch from the latest main/develop.
- Never commit directly to main or develop.

## Quality Standards

- Run tests before AND after every change.
- No TODO comments without a linked ticket ID.
- Every function must handle its error paths.
- Never hardcode values that should be configurable.
- Validate all external input at system boundaries.
- Never suppress linter warnings without a comment explaining why.

## Documentation

- Update PROGRESS.md after completing any task.
- Add entries to docs/lessons-learned.md when discovering non-obvious solutions.
- Update the relevant ADR when making architectural decisions.

## Anti-Rationalization

- "Too simple to test" — Simple code breaks. Write the test.
- "I'll add tests later" — You won't. Write them now.
- "I've completed the task" — Did you run it? Verify before claiming completion.
- "That's outside the scope" — If it breaks or is a security risk, it is in scope.

## Domain Rules

- See .claude/rules/api-routes.md for API route files.
- See .claude/rules/database.md for database/migration files.
- See .claude/rules/components.md for UI component files.
- See .claude/rules/tests.md for test files.
- See .claude/rules/documentation.md for documentation files.
