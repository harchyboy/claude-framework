# Composable Flags

Flags that modify ANY command's behaviour. Commands parse these from `$ARGUMENTS`
before processing the remaining input.

## Flag definitions

| Flag | Short | Effect |
|------|-------|--------|
| `--readonly` | `-r` | No file writes. Analysis and search only. |
| `--concise` | `-c` | Output max 20 lines. Summary only. No verbose formatting. |
| `--lean` | `-l` | Use haiku model for subagents. Minimize tool calls. Skip optional enrichment. |
| `--seq` | `-s` | Sequential execution only. No parallel agent spawning. |
| `--local` | `--lo` | Route eligible subtasks to Ollama. Falls back to haiku if unavailable. Implies `--lean`. |

## Parsing protocol

Every command MUST parse composable flags before processing `$ARGUMENTS`:

1. Scan `$ARGUMENTS` for any of: `--readonly`, `-r`, `--concise`, `-c`, `--lean`, `-l`, `--seq`, `-s`, `--local`, `--lo`
2. Record which flags are active
3. Strip the flags from `$ARGUMENTS` — the remainder is the command's actual input
4. Apply flag behaviours throughout execution

## Flag behaviours in detail

### --readonly

- Do NOT create, edit, or delete any files
- Do NOT spawn agents with Write or Edit tools
- Limit agent tools to: Read, Glob, Grep, Bash (read-only commands only)
- Useful for: exploration, understanding, planning without side effects
- Example: `/review --readonly` analyses code without creating tasks or updating PROGRESS.md

### --concise

- Total output must be under 20 lines
- Skip detailed explanations — give the actionable answer only
- No verbose report formatting (skip box-drawing, headers, separators)
- Skip "Why this exists" and background sections
- Example: `/status --concise` gives a 5-line summary instead of a full briefing

### --lean

- Override subagent model to `haiku` instead of `sonnet`
- Minimize tool calls — batch where possible
- Skip optional enrichment steps (learnings check, related docs search)
- Target: lowest-cost execution path
- Example: `/review --lean` runs cheaper agents without learnings integration

### --seq

- Never spawn multiple agents in parallel — execute one at a time
- Each agent must complete before the next starts
- Useful for: debugging agent interactions, low-resource environments, reading outputs in order
- Example: `/debug --seq` runs investigators one at a time instead of all three at once

### --local (--lo)

- For each subtask, call `bash scripts/route-model.sh --task-type <type> --check-local` to determine route
- If route is `local:<model>`: run `bash scripts/local-model.sh --task-type <type> - <<< "$PROMPT"` via Bash tool
- If Ollama unavailable: fall back to haiku (same as `--lean`)
- Implies `--lean` — all cloud subagents also use haiku when local model is not applicable
- Eligible task types: `classify`, `test-scaffold`, `docs`, `lint-fix`, `boilerplate`, `summarize`
- NOT eligible (always cloud): security, architecture, feature implementation, bug-fix
- Example: `/task --local Add loading spinner` → classification via local model, implementation via haiku if simple

## Flag combinations

Flags compose naturally. Common combinations:

| Command | Effect |
|---------|--------|
| `/review --readonly --concise` | Read-only review, summary output |
| `/debug --lean --seq` | Cheap, sequential debugging |
| `/research --deep --concise` | Deep research, brief output |
| `/status --concise` | One-line status |
| `/task --readonly` | Classify and plan without implementing |
| `/intake --concise` | Quick intake summary, minimal formatting |
| `/task --local` | Classify + quick tasks via Ollama, fall back to haiku |
| `/review --local --concise` | Cheapest possible review pass |

## Integration with commands

Each command file includes a standard composable flags section that references this doc.
The section is placed early in the command so flags are parsed before main logic executes.

Standard block for command files:

```
## Composable flags

Before processing $ARGUMENTS, parse composable flags per `.claude/docs/composable-flags.md`.
Strip recognized flags (--readonly, --concise, --lean, --seq and their short forms)
from $ARGUMENTS before treating the remainder as this command's input.

Apply active flags throughout:
- --readonly: skip all file writes and write-capable agent spawns
- --concise: limit output to 20 lines max
- --lean: use haiku for subagents, minimize tool calls
- --seq: execute agents sequentially, not in parallel
- --local/--lo: for any eligible subtask, run `bash scripts/local-model.sh` via Bash tool instead of spawning a Claude subagent; fall back to haiku if Ollama unavailable
```
