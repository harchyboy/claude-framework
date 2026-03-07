# Hartz Claude Framework

> Stack-agnostic engineering DNA for autonomous AI development. CLAUDE.md hierarchy, TDD agents, quality gate hooks, review agents, and CI/CD templates — synced across all projects via git submodule.

---

## What is HCF

HCF is a template repository that standardises how Claude Code agents operate across all Hartz AI projects. It provides:

- **CLAUDE.md hierarchy** — root rules + glob-scoped domain rules (api, database, components, tests, docs)
- **TDD subagent pipeline** — isolated red/green/refactor agents that enforce test-first development
- **Review agents** — quality, adversarial (3+ findings required), and security reviewers
- **Quality gate hooks** — auto-lint, pre-PR gate, pre-commit validation, session handoff
- **CI/CD templates** — GitHub Actions for automated testing and agent-powered PR review
- **Document templates** — Shape Up pitches, standups, blockers, ADRs

---

## Architecture

```
hartz-claude-framework/
├── .claude/
│   ├── CLAUDE.md                    # Root config (<150 lines, imperative voice)
│   ├── settings.json                # Hook configurations
│   ├── agents/
│   │   ├── tdd-red.md               # RED: writes failing tests from specs
│   │   ├── tdd-green.md             # GREEN: minimum implementation to pass
│   │   ├── tdd-refactor.md          # REFACTOR: improves without breaking tests
│   │   ├── quality-reviewer.md      # Code quality (1+ substantive findings)
│   │   ├── adversarial-reviewer.md  # Devil's advocate (3+ issues required)
│   │   └── security-reviewer.md     # OWASP Top 10, auth, injection, secrets
│   ├── hooks/
│   │   ├── auto-lint.sh             # PostToolUse: auto-format after edits
│   │   ├── pre-pr-gate.sh           # PreToolUse: blocks PR without tests
│   │   ├── pre-commit-gate.sh       # PreToolUse: validates commit messages
│   │   └── session-end.sh           # Stop: structured handoff + healthcheck
│   ├── handoff/                     # Session handoff files
│   └── rules/
│       ├── api-routes.md            # REST conventions, validation, error handling
│       ├── database.md              # Migration safety, queries, indexes
│       ├── components.md            # Props, accessibility, responsive design
│       ├── tests.md                 # AAA pattern, isolation, mock boundaries
│       └── documentation.md         # ADR format, docstrings, changelogs
├── .github/workflows/
│   ├── ci-template.yml              # Stack-agnostic quality gate pipeline
│   └── agent-review.yml             # Parallel agent review via claude-code-action
└── docs/templates/
    ├── pitch.md                     # Shape Up pitch format
    ├── standup.md                   # Agent daily standup
    ├── blocker.md                   # Blocker escalation (3 levels)
    └── adr-template.md              # Architecture Decision Record (MADR)
```

---

## Quick Start

```bash
# Add as submodule
git submodule add https://github.com/harchyboy/claude-framework .claude-framework

# Run installer
bash .claude-framework/install.sh .

# Edit CLAUDE.md — replace [REPLACE] placeholders with project details
```

---

## Agent Reference

| Agent | Purpose | Tools |
|-------|---------|-------|
| `tdd-red` | Writes failing tests from specs (RED phase) | Read, Write, Bash, Glob, Grep |
| `tdd-green` | Minimum implementation to pass tests (GREEN) | Read, Write, Bash, Glob, Grep |
| `tdd-refactor` | Improves code quality, reverts on failure | Read, Write, Edit, Bash, Glob, Grep |
| `quality-reviewer` | SOLID, DRY, complexity, coverage gaps | Read, Glob, Grep, Bash |
| `adversarial-reviewer` | 3+ specific issues required per review | Read, Glob, Grep, Bash |
| `security-reviewer` | OWASP Top 10, auth, injection, secrets | Read, Glob, Grep, Bash |

### TDD Pipeline

```
Spec → [tdd-red] → Failing Tests → [tdd-green] → Passing Code → [tdd-refactor] → Clean Code
```

Each agent runs in an isolated context window. The red agent cannot see implementation. The green agent cannot modify tests. This prevents the LLM from cheating by reverse-engineering tests from code.

---

## Hook Reference

| Hook | Trigger | Behaviour |
|------|---------|-----------|
| `auto-lint.sh` | PostToolUse (Edit) | Runs prettier (JS/TS) or ruff (Python) silently |
| `pre-pr-gate.sh` | PreToolUse (PR creation) | Blocks if tests fail, coverage < threshold, or lint errors |
| `pre-commit-gate.sh` | PreToolUse (git commit) | Validates conventional commit format with ticket ID |
| `session-end.sh` | Stop | Writes structured handoff with belief statements |

### Pre-PR Gate

Detects project stack automatically (package.json, pyproject.toml, Cargo.toml). Configurable:

- `COVERAGE_THRESHOLD` — minimum coverage % (default: 80)
- `MUTATION_TESTING=true` — runs Stryker (JS) or mutmut (Python)

Full output goes to `.claude/hooks/logs/`. Only summaries print to stdout.

---

## CI/CD Templates

**ci-template.yml** — Stack-agnostic pipeline: lint, typecheck, unit tests, integration tests, coverage gate, semgrep security scan. Copy to your project's `.github/workflows/`.

**agent-review.yml** — Triggers quality + adversarial + security review agents on every PR via `anthropics/claude-code-action`. Requires `ANTHROPIC_API_KEY` repository secret.

---

## Customisation

### Project-level overrides

Projects override framework defaults by:

1. Adding project-specific rules to their own `.claude/rules/` directory
2. Setting environment variables for hook thresholds (`COVERAGE_THRESHOLD`, `MUTATION_TESTING`)
3. Modifying their project-level `CLAUDE.md` (the root `.claude/CLAUDE.md` provides defaults)

### Stack detection

All hooks and CI templates detect the project stack dynamically:
- `package.json` → Node/TypeScript (npm, jest/vitest, eslint/biome, prettier)
- `pyproject.toml` / `setup.py` → Python (pytest, ruff/flake8, black)
- `Cargo.toml` → Rust (cargo test, clippy)

---

## Document Templates

| Template | Purpose | Location |
|----------|---------|----------|
| `pitch.md` | Shape Up feature pitch (problem, appetite, solution, rabbit holes, no-gos) | `docs/templates/` |
| `standup.md` | Agent daily standup (completed, blockers, metrics) | `docs/templates/` |
| `blocker.md` | Escalation report (3 levels: retry, skip, human) | `docs/templates/` |
| `adr-template.md` | Architecture Decision Record (MADR format) | `docs/templates/` |

---

## Contributing

1. Create a feature branch: `[PROJECT]-[TICKET]-[description]`
2. Follow conventional commits: `type(scope): description [TICKET-ID]`
3. All code must pass the pre-PR quality gate
4. Every PR gets reviewed by quality + adversarial + security agents
5. Update this README if adding new agents, hooks, or templates

---

Maintained by [Hartz AI](https://hartz.ai). MIT License.
