# Local Model Routing

HCF automatically routes low-complexity tasks to a local Ollama instance when available,
saving Claude API tokens for work that genuinely needs them.

## How it works

Three components cooperate:

1. **`scripts/route-model.sh`** — classifies a task description and returns the recommended
   execution path: `local:<model>`, `haiku`, `sonnet`, or `opus`.

2. **`scripts/local-model.sh`** — sends a prompt to Ollama with automatic model selection
   based on task type, falling back to Claude if Ollama is unavailable.

3. **`ralph.sh` auto-routing** — before each story iteration, classifies the story type and
   attempts Ollama pre-generation for eligible types. Claude then verifies and refines.

## Task type routing table

| Task type | Local model | Cloud fallback | Notes |
|-----------|-------------|----------------|-------|
| `classify` | qwen2.5-coder:3b | haiku | Triage, routing decisions |
| `summarize` | qwen2.5-coder:3b | haiku | Condense long context |
| `lint-fix` | qwen2.5-coder:3b | haiku | Format/lint corrections |
| `test-scaffold` | qwen2.5-coder:7b | haiku | Test file skeletons |
| `boilerplate` | qwen2.5-coder:7b | haiku | CRUD/component stubs |
| `docs` | qwen2.5-coder:7b | haiku | JSDoc, README, docstrings |
| `explore` | — | haiku | Codebase search |
| `simple-edit` | — | haiku | Single-file copy change |
| `feature` | — | sonnet | Product feature work |
| `bug-fix` | — | sonnet | Debug and fix |
| `refactor` | — | sonnet | Restructuring |
| `review` | — | sonnet | Code quality |
| `security` | — | opus | Auth, RLS, OWASP |
| `architecture` | — | opus | System design, ADRs |
| `orchestrate` | — | opus | Multi-agent coordination |
| `escalate` | — | opus | 3+ failed attempts |

## Automatic detection

`route-model.sh --description` classifies from natural language:

```bash
# Returns "local:qwen2.5-coder:7b" if Ollama available, else "haiku"
ROUTE=$(bash scripts/route-model.sh \
  --description "Write unit tests for UserService" \
  --check-local \
  --quiet)
```

`classify_story()` in `ralph.sh` does the same for PRD story titles:

| Title keywords | Story type |
|----------------|------------|
| "write test", "generate test", "test for" | `test-scaffold` |
| "jsdoc", "docstring", "readme", "document" | `docs` |
| "lint", "fix warning", "unused import", "prettier" | `lint-fix` |
| "boilerplate", "scaffold", "stub", "crud for" | `boilerplate` |
| (anything else) | `feature` — uses Claude |

## ralph.sh behaviour

Ralph auto-routes by default (`--use-local` is on). Per iteration:

1. Story picked → title + description extracted from PRD
2. `classify_story()` determines type
3. If type is `test-scaffold`, `docs`, `lint-fix`, or `boilerplate`:
   - Checks if Ollama is reachable at `$OLLAMA_HOST`
   - If yes: runs `local-model.sh` to pre-generate file content
   - Parses `=== FILE: path ===` blocks from output and writes them
   - Runs quality gate if `--quality-gate` flag is set
   - If quality gate passes: Claude uses haiku to verify/refine (much cheaper)
   - If quality gate fails or local model errors: falls through to full Claude sonnet
4. If type is `feature`: skips local routing, runs Claude sonnet directly

Disable with `--no-local`:
```bash
bash scripts/ralph.sh --no-local
```

## Composable flag: `--local`

Add `--local` (or `--lo`) to any command to enable local routing:

```bash
/task --local Write unit tests for the payment module
/review --local --concise
```

When active:
- Classification step uses Ollama instead of Claude API
- Quick tasks (eligible types above) execute fully via Ollama
- All cloud subagents use haiku (same as `--lean`)
- Falls back gracefully if Ollama is unavailable

## Ollama setup

```bash
# Install (if not already)
curl -fsSL https://ollama.ai/install.sh | sh

# Pull recommended models
ollama pull qwen2.5-coder:7b   # main code generation model
ollama pull qwen2.5-coder:3b   # fast classification and lint fixes

# Verify
curl http://localhost:11434/api/tags
```

Override host:
```bash
OLLAMA_HOST=http://192.168.1.10:11434 bash scripts/ralph.sh
```

Override default model:
```bash
LOCAL_MODEL=codellama:13b bash scripts/ralph.sh
```

## Fallback chain

```
Task arrives
    │
    ▼
Ollama available? ──No──► haiku (for eligible types)
    │                         │
   Yes                        ▼
    │                    sonnet / opus (for complex types)
    ▼
Local model runs
    │
   Fail ──────────────► haiku fallback
    │
  Success
    │
    ▼
Output accepted
```
