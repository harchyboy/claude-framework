# /intake — Client Feedback Intake

Parses client feedback documents and decomposes them into classified,
prioritised work items — then generates PRDs and routes each to the
right workflow automatically.

## Usage

```
/intake docs/client-feedback.pdf
/intake [paste feedback text directly]
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

## Recommended format: PDF

PDF is the best format because Claude can see both text AND images.
Screenshots, annotated mockups, circled elements, highlighted areas — all visible.

If the client sends Word (.docx), save as PDF first.
For large PDFs (10+ pages), read in chunks using pages parameter.

## What I'll do

1. **Read** the document — use the Read tool to view the PDF, seeing all text AND screenshots/annotations
2. **Describe every screenshot** — for each image, annotated mockup, or highlighted area, write what you see: the current state, what the client has marked, and what they appear to want changed
3. **Extract** individual items — each bug, UX change, content update, or feature request becomes a separate item. Screenshots often contain multiple items — extract each one
4. **Classify** each item:
   - BUG — something is broken or behaving incorrectly
   - UX — layout, flow, visual, or interaction change to existing feature
   - FEATURE — new functionality that doesn't exist yet
   - CONTENT — text, copy, or asset changes
   - UNCLEAR — needs clarification before proceeding
5. **Cross-reference with codebase** — for each item, Glob/Grep to find the relevant files so the PRD targets the right code
6. **Deduplicate** — check against existing PRDs in docs/prds/ and PROGRESS.md to avoid duplicate work
7. **Prioritise** using this severity order:
   - P1 CRITICAL — broken functionality, data loss, security issue
   - P2 HIGH — major UX regression, blocking user workflow
   - P3 MEDIUM — UX improvement, minor bug, enhancement
   - P4 LOW — cosmetic, copy change, nice-to-have
8. **Present the intake summary** for approval before generating anything
9. **Generate PRDs** — one per item (or grouped if tightly related)
10. **Route** — bugs to /bugfix workflow, features/UX/content to /prd workflow

## Reading the document

For PDFs, read in page chunks:
- Small docs (1-10 pages): `Read` the entire file
- Large docs (10+ pages): `Read` with `pages: "1-10"`, then `pages: "11-20"`, etc.

For each page, extract:
- **Text content**: what the client wrote
- **Screenshots**: describe exactly what you see — current UI state, annotations, arrows, circles, highlights, crossed-out areas, handwritten notes
- **Context clues**: page headers, section titles, feature names that help locate the relevant code

## Screenshot interpretation guide

When you see annotated screenshots:
- **Red circles/arrows** → "this element has an issue" or "look here"
- **Crossed out elements** → "remove this" or "this is wrong"
- **Handwritten text/annotations** → the client's desired change
- **Side-by-side comparisons** → "change from this to this"
- **Highlighted text** → "this specific text needs to change"
- **Before/after mockups** → "make it look like this instead"

Always describe what you see in the screenshot AND what change the client appears to want. If ambiguous, mark as UNCLEAR.

## Intake summary format

Present this table before generating PRDs:

```
## Intake Summary — [source document]
## Date: YYYY-MM-DD
## Pages reviewed: [count]
## Screenshots found: [count]

| # | Type | Priority | Summary | Source | Files | Action |
|---|------|----------|---------|--------|-------|--------|
| 1 | BUG | P1 | Image upload fails silently over 5MB | p.3 text | src/upload/ | /bugfix |
| 2 | UX | P3 | Move save button to top-right corner | p.5 screenshot | src/components/Form.tsx | /prd |
| 3 | FEATURE | P2 | Add export to CSV on reports page | p.7 text | src/pages/Reports.tsx | /prd |
| 4 | CONTENT | P4 | Update footer copyright to 2026 | p.8 screenshot | src/components/Footer.tsx | /prd |
| 5 | UNCLEAR | — | Annotation says "make bigger" but unclear which element | p.4 screenshot | — | ASK |

## Screenshot Descriptions:
- p.5: Dashboard view with red arrow pointing at save button (bottom-left). Client wants it moved to top-right.
- p.8: Footer screenshot with "2025" circled in red. Client wants "2026".
- p.4: Settings page with "make bigger" written next to sidebar. Unclear if referring to sidebar width, font size, or button size.

## Items requiring clarification:
- Item 5: "make bigger" on p.4 — which element? Sidebar? Font? Buttons?
```

## After approval

Wait for approval. You might hear:
- "Do all of them" → generate PRDs for everything, route each
- "Do 1, 2, and 3" → generate only those
- "Skip 4, clarify 5" → hold those, proceed with the rest
- "Change 2 to P2" → adjust priority before generating

Then for each approved item:
1. Generate a prd.json in docs/prds/intake-YYYY-MM-DD-NNN/
2. Include the original client wording and screenshot description for traceability
3. Include the target file paths found during cross-referencing
4. Route to the appropriate workflow

## Rules

- Never skip the approval step. Always present the summary first.
- Never guess at UNCLEAR items. Ask.
- Always describe what you see in screenshots. Never say "see screenshot" — write what is in it.
- Group tightly related items (e.g., 3 bugs all in the same form) into one PRD.
- Keep items that touch different areas of the codebase as separate PRDs.
- Include the original client wording in each PRD for traceability.
- Cross-reference every item against the actual codebase to find target files.
- If a screenshot shows UI elements, grep the codebase for matching component names, text strings, or CSS classes to locate the code.
