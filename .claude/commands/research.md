# /research — Graduated Depth Research

Research a topic with configurable depth. Uses internal codebase search,
web search, and MCP tools based on the selected depth level.

## Usage

```
/research [topic]                    → Standard depth (default)
/research --quick [topic]            → Codebase only, 2-3 sources
/research --standard [topic]         → Codebase + web, 5-8 sources
/research --deep [topic]             → Multi-iteration, 10-15 sources
/research --exhaustive [topic]       → Comprehensive, 20+ sources
```

## Composable flags

Before processing $ARGUMENTS, parse composable flags per `.claude/docs/composable-flags.md`.
Strip recognized flags (--readonly, --concise, --lean, --seq, --local and their short forms)
from $ARGUMENTS before treating the remainder as this command's input.

Apply active flags throughout:
- --readonly: skip all file writes and write-capable agent spawns
- --concise: limit output to 20 lines max
- --lean: use haiku for subagents, minimize tool calls
- --seq: execute agents sequentially, not in parallel
- --local: route eligible subtasks to Ollama, fall back to haiku if unavailable

## Depth levels

| Level | Sources | Search iterations | Web tools | MCP scraping | Output style |
|-----------|---------|-------------------|-----------|--------------|--------------|
| quick | 2-3 | 1 | No | No | Bullet points |
| standard | 5-8 | 2 | WebSearch | No | Summary + sources |
| deep | 10-15 | 3-4 | WebSearch + WebFetch | Yes | Structured report |
| exhaustive | 20+ | 5+ | All available | Yes | Full report + bibliography |

## Argument parsing

1. Extract depth flag from $ARGUMENTS: look for `--quick`, `--standard`, `--deep`, `--exhaustive`
2. If no depth flag present, default to `--standard`
3. Everything remaining after stripping depth flag and composable flags is the research topic
4. Parse composable flags first, then depth flag, then treat the rest as the topic

## What to do

### Step 1: Internal research (ALL levels)

Search the local codebase and project knowledge:
1. Search `docs/solutions/` for related entries (Glob + Grep)
2. Search the codebase via Glob/Grep for related code, configs, and docs
3. Check `docs/failed-approaches.md` for relevant past failures
4. Check `PROGRESS.md` for related ongoing work
5. Check `.claude/handoff/session-summary.md` for recent context

For `--quick`: STOP HERE. Synthesise internal findings and output.

### Step 2: Web research (standard and above)

Use WebSearch to find relevant articles, documentation, and discussions.

| Level | Queries | Results to read |
|-----------|---------|-----------------|
| standard | 2 | Top 3-5 |
| deep | 3-4 | Top 5-8 |
| exhaustive | 5+ | Top 10+ |

Refine search queries between iterations based on what you learn.
Use different query angles (e.g., "how to X", "X best practices", "X vs Y", "X common pitfalls").

For `--standard`: synthesise findings after this step.

### Step 3: Deep source analysis (deep and above)

1. Use WebFetch to read the full content of the most promising search results
2. Use `mcp__claude_ai_Bright_Data__scrape_as_markdown` for pages that WebFetch struggles with
3. Cross-reference findings across sources — note consensus and contradictions
4. For `--exhaustive`: use `mcp__claude_ai_Bright_Data__search_engine` for additional search coverage beyond WebSearch

### Step 4: Codebase exploration (deep and above, when topic is code-related)

If the research topic relates to implementation patterns or architecture:
1. Spawn an Explore agent to find relevant patterns in the codebase
2. Compare findings with external best practices from Steps 2-3
3. Identify gaps between current implementation and discovered best practices

For `--deep`: synthesise findings after this step.

### Step 5: Exhaustive synthesis (exhaustive only)

1. Spawn 2-3 research agents in parallel (unless --seq), each covering a different angle:
   - Agent A: Technical implementation approaches
   - Agent B: Trade-offs, risks, and failure modes
   - Agent C: Community consensus and real-world usage patterns
2. Merge findings, resolve contradictions, assign confidence ratings

## Output format

### --quick output

```
RESEARCH: [topic]
───────────────────

• [Finding 1] — [source: file or doc]
• [Finding 2] — [source]
• [Finding 3] — [source]

Confidence: [HIGH/MEDIUM/LOW]
```

### --standard output

```
═══════════════════════════════════════
RESEARCH REPORT — [topic] — [date]
═══════════════════════════════════════

SUMMARY
───────
[2-3 paragraph synthesis of findings]

KEY FINDINGS
────────────
1. [Finding] — [source with link]
2. [Finding] — [source with link]
3. [Finding] — [source with link]

RELEVANCE TO THIS PROJECT
──────────────────────────
[How findings apply to the current codebase/task]

SOURCES
───────
- [Source 1 — title and URL]
- [Source 2 — title and URL]
```

### --deep output

```
═══════════════════════════════════════
DEEP RESEARCH REPORT — [topic] — [date]
═══════════════════════════════════════

EXECUTIVE SUMMARY
──────────────────
[1 paragraph — the answer, stated directly]

DETAILED FINDINGS
─────────────────

## [Subtopic 1]
[Detailed analysis with evidence]
Sources: [1], [2]

## [Subtopic 2]
[Detailed analysis with evidence]
Sources: [3], [4]

## [Subtopic 3]
[Detailed analysis with evidence]
Sources: [5], [6]

TRADE-OFFS & RISKS
───────────────────
| Approach | Pros | Cons | Risk level |
|----------|------|------|------------|
| [A] | ... | ... | LOW |
| [B] | ... | ... | MEDIUM |

RECOMMENDATION
──────────────
[Specific recommendation with justification]

CODEBASE IMPACT
───────────────
[How this applies to the current project, specific files/patterns affected]

SOURCES ([count])
─────────────────
[Numbered source list with URLs]
```

### --exhaustive output

Same structure as --deep, plus:

```
CONFIDENCE RATINGS
──────────────────
| Finding | Confidence | Source agreement | Notes |
|---------|------------|-----------------|-------|
| [1] | HIGH | 4/5 sources agree | ... |
| [2] | MEDIUM | Mixed signals | ... |

CONTRADICTIONS & OPEN QUESTIONS
────────────────────────────────
- [Source A] says X, but [Source B] says Y. Likely explanation: ...
- Unresolved: [question that needs more investigation]

BIBLIOGRAPHY
────────────
[Full list of all sources consulted, with dates and relevance notes]
```
