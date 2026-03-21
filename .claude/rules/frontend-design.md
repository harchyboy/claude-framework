# Frontend Design Quality Rules
# Applies to: **/*.html, **/*.css, **/*.scss, **/*.jsx, **/*.tsx, **/*.vue, **/*.svelte
# Source: Anthropic's frontend-design skill (anthropics/skills)
#
# These rules activate alongside components.md and design-system.md for any frontend file.
# components.md handles structure and accessibility.
# design-system.md handles the technical contract: tokens, registry, and primitives.
# This file handles design quality and aesthetic direction.

Create distinctive, production-grade frontend interfaces with high design quality. Generates creative, polished code and UI design that avoids generic AI aesthetics.

## Design Thinking

Before coding, understand the context and commit to a BOLD aesthetic direction:
- **Purpose**: What problem does this interface solve? Who uses it?
- **Tone**: Pick an extreme: brutally minimal, maximalist chaos, retro-futuristic, organic/natural, luxury/refined, playful/toy-like, editorial/magazine, brutalist/raw, art deco/geometric, soft/pastel, industrial/utilitarian, etc. There are so many flavors to choose from. Use these for inspiration but design one that is true to the aesthetic direction.
- **Constraints**: Technical requirements (framework, performance, accessibility).
- **Differentiation**: What makes this UNFORGETTABLE? What's the one thing someone will remember?

**CRITICAL**: Choose a clear conceptual direction and execute it with precision. Bold maximalism and refined minimalism both work - the key is intentionality, not intensity.

Then implement working code (HTML/CSS/JS, React, Vue, etc.) that is:
- Production-grade and functional
- Visually striking and memorable
- Cohesive with a clear aesthetic point-of-view
- Meticulously refined in every detail

## Frontend Aesthetics Guidelines

Focus on:
- **Typography**: Choose fonts that are beautiful, unique, and interesting. Avoid generic fonts like Arial and Inter; opt instead for distinctive choices that elevate the frontend's aesthetics; unexpected, characterful font choices. Pair a distinctive display font with a refined body font.
- **Color & Theme**: Commit to a cohesive aesthetic. Use CSS variables for consistency. Dominant colors with sharp accents outperform timid, evenly-distributed palettes.
- **Motion**: Use animations for effects and micro-interactions. Prioritize CSS-only solutions for HTML. Use Motion library for React when available. Focus on high-impact moments: one well-orchestrated page load with staggered reveals (animation-delay) creates more delight than scattered micro-interactions. Use scroll-triggering and hover states that surprise.
- **Spatial Composition**: Unexpected layouts. Asymmetry. Overlap. Diagonal flow. Grid-breaking elements. Generous negative space OR controlled density.
- **Backgrounds & Visual Details**: Create atmosphere and depth rather than defaulting to solid colors. Add contextual effects and textures that match the overall aesthetic. Apply creative forms like gradient meshes, noise textures, geometric patterns, layered transparencies, dramatic shadows, decorative borders, custom cursors, and grain overlays.

## Anti-Patterns (Never Do These)

NEVER use generic AI-generated aesthetics:
- Overused font families (Inter, Roboto, Arial, system fonts) as primary display fonts
- Cliched color schemes (particularly purple gradients on white backgrounds)
- Predictable layouts and component patterns (centered hero + 3-column feature cards)
- Cookie-cutter design that lacks context-specific character
- Converging on the same "safe" choices (e.g., Space Grotesk) across different projects

Interpret creatively and make unexpected choices that feel genuinely designed for the context. No design should be the same. Vary between light and dark themes, different fonts, different aesthetics.

## Implementation Complexity

Match implementation complexity to the aesthetic vision:
- Maximalist designs need elaborate code with extensive animations and effects
- Minimalist or refined designs need restraint, precision, and careful attention to spacing, typography, and subtle details
- Elegance comes from executing the vision well, not from adding more

## Design System Integration

When a project has a design system set up (see `design-system.md`):

- **Tokens are your palette** — all color, spacing, typography, and radii values come from `tokens/design-tokens.json`. Express your aesthetic direction through token selection and composition, not arbitrary values.
- **shadcn/ui is your component vocabulary** — compose from registry components. Customize via Tailwind classes and `cn()`, not by forking or rewriting primitives.
- **Figma MCP is your design source** — when a Figma file exists, read it before generating. The design is the spec; don't improvise over it.
- **Magic UI MCP generates variations** — request 2-3 variations for key components, then select the best fit for the aesthetic direction.

## Tooling Quick Reference

| Need | Tool |
|------|------|
| Scaffold a new frontend project | `/ui-scaffold` skill |
| Build a component from a design | `workflows/ui-component.yaml` |
| Generate a component from a prompt | Magic UI MCP (`mcp__magic-ui__21st_magic_component_builder`) |
| Discover registry components | shadcn MCP server |
| Read a Figma design | Figma MCP server (`FIGMA_API_KEY` required) |
| Visual regression testing | `agent-browser screenshot` |
