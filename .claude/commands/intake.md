# /intake — Client Feedback Intake

Parses client feedback documents (Word, PDF, plain text, pasted text) and
decomposes them into classified, prioritised work items — then generates PRDs
and routes each to the right workflow automatically.

## Usage

```
/intake path/to/client-feedback.docx
/intake path/to/ux-review.pdf
/intake [paste feedback text directly]
```

## What I'll do

1. **Parse** the document — extract all text, identify screenshots/annotations if referenced
2. **Extract** individual items — each bug, UX change, content update, or feature request becomes a separate item
3. **Classify** each item:
   - BUG — something is broken or behaving incorrectly
   - UX — layout, flow, visual, or interaction change to existing feature
   - FEATURE — new functionality that doesn't exist yet
   - CONTENT — text, copy, or asset changes
   - UNCLEAR — needs clarification from you before proceeding
4. **Deduplicate** — check against existing PRDs in docs/prds/ and PROGRESS.md to avoid duplicate work
5. **Prioritise** using this severity order:
   - P1 CRITICAL — broken functionality, data loss, security issue
   - P2 HIGH — major UX regression, blocking user workflow
   - P3 MEDIUM — UX improvement, minor bug, enhancement
   - P4 LOW — cosmetic, copy change, nice-to-have
6. **Present the intake summary** for your approval before generating anything
7. **Generate PRDs** — one per item (or grouped if tightly related)
8. **Route** — bugs → `/bugfix` workflow, features → `/prd` workflow, UX/content → `/prd` with appropriate sizing

## Parsing rules

**Word documents (.docx):**
- Extract all text content, preserving headings as item boundaries
- Numbered lists and bullet points are likely separate items
- Bold or highlighted text often indicates the key issue
- "Should be" / "Expected" / "Instead" patterns indicate bugs
- "Can we" / "Add" / "Change" / "Move" patterns indicate UX/feature requests

**PDF files (.pdf):**
- Extract text, treat annotations and comments as separate items
- Screenshot references (e.g., "see attached", "as shown") — note them but work from the text description

**Pasted text:**
- Split on numbered items, bullet points, or blank-line-separated paragraphs
- Each distinct issue is a separate item

## Intake summary format

Present this table before generating PRDs:

```
## Intake Summary — [source document]
## Date: YYYY-MM-DD

| # | Type | Priority | Summary | Action |
|---|------|----------|---------|--------|
| 1 | BUG | P1 | Image upload fails silently over 5MB | /bugfix |
| 2 | UX | P3 | Move save button to top-right corner | /prd |
| 3 | FEATURE | P2 | Add export to CSV on reports page | /prd |
| 4 | CONTENT | P4 | Update footer copyright to 2026 | /prd |
| 5 | UNCLEAR | — | "Make it more modern" (needs clarification) | ASK |

## Items requiring clarification:
- Item 5: "Make it more modern" — what specifically? Colour scheme? Typography? Layout?
```

## After approval

Wait for you to say which items to proceed with. You might say:
- "Do all of them" → generate PRDs for everything, route each
- "Do 1, 2, and 3" → generate only those
- "Skip 4, clarify 5" → hold those, proceed with the rest
- "Change 2 to P2" → adjust priority before generating

Then for each approved item:
1. Generate a prd.json in docs/prds/intake-YYYY-MM-DD-NNN/
2. Route to the appropriate workflow
3. Report what was generated

## Rules

- Never skip the approval step. Always present the summary first.
- Never guess at UNCLEAR items. Ask.
- Group tightly related items (e.g., 3 bugs all in the same form) into one PRD.
- Keep items that touch different areas of the codebase as separate PRDs.
- Include the original client wording in each PRD for traceability.
- If the document references screenshots or mockups you can't see, note what's missing and ask.
