# Documentation Rules
# Applies to: **/*.md, **/docs/**, **/README*, **/CHANGELOG*

- Use ADR format (see docs/templates/adr-template.md) for all architectural decisions.
- Write for the reader who has no prior context. Avoid jargon without definition.
- Keep README files under 300 lines. Link to detailed docs for depth.
- Update CHANGELOG.md with every user-facing change.
- Use code blocks with language tags for all code examples.
- Include "last updated" dates on living documents.
- JSDoc/docstrings: document public APIs, parameters, return values, and thrown errors.
- Never document implementation details that change frequently — document intent and contracts.
- Diagrams: use Mermaid or ASCII art that renders in GitHub markdown.
- Every new feature requires a corresponding documentation update.
