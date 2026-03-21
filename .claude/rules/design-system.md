# Design System Rules
# Applies to: **/components/**, **/*.tsx, **/*.jsx, **/*.vue, **/*.svelte, **/*.css, **/*.scss
#
# These rules activate alongside components.md and frontend-design.md.
# components.md handles structure/accessibility, frontend-design.md handles aesthetics.
# This file enforces the design system contract: tokens, registry, and primitives.

## Stack (When Project Uses React)

The default frontend stack for Hartz AI projects is:
- **shadcn/ui** — copy-paste component library (not an npm dependency)
- **Tailwind v4** — CSS-first configuration via `@theme` directive
- **Radix UI** — headless accessible primitives (used by shadcn/ui)
- **W3C DTCG tokens** — design token source of truth in `tokens/` directory

Projects may use Vue (shadcn-vue), Svelte (shadcn-svelte), or other frameworks.
The principles below apply regardless of framework.

## Token-Only Styling

All visual values MUST come from the project's design token system:

- **Use Tailwind utility classes** that map to theme tokens (`bg-primary`, `text-muted-foreground`, `rounded-lg`)
- **Use CSS variables** defined in the project's `@theme` or `:root` block
- **Never use Tailwind arbitrary values** like `text-[#ff0000]`, `p-[13px]`, `bg-[var(--custom)]`
  - Exception: one-off layout values (`w-[calc(100%-2rem)]`) where no token applies
- **Never use inline styles** for colors, spacing, typography, or radii
- **Never hardcode hex/rgb/hsl values** in component files — define them as tokens first

If a value you need doesn't exist as a token, add it to the token system — don't bypass it.

## Registry-Only Components

When a project has shadcn/ui installed:

- **Use existing registry components** before building custom ones. Run `npx shadcn add <component>` to install what you need.
- **Check the registry first**: Button, Card, Dialog, Dropdown, Input, Select, Table, Tabs, Toast, Sheet, etc.
- **Compose from primitives** — build complex UI by combining registry components, not by creating monolithic custom components.
- **Custom components** must follow shadcn conventions: use `cn()` utility, accept `className` prop, forward refs, use Tailwind for styling.
- **Never recreate** a component that exists in the registry (no custom Modal when Dialog exists, no custom Dropdown when DropdownMenu exists).

## Radix-Only Interactivity

All interactive UI patterns MUST use headless primitives (Radix UI, or framework equivalent):

- **Dialogs/Modals**: Use `Dialog` primitive — never `<div onClick>` with `display:none` toggling
- **Dropdowns**: Use `DropdownMenu` — never custom `<ul>` with click-outside handlers
- **Tooltips**: Use `Tooltip` — never `title` attribute or custom hover `<div>`
- **Tabs**: Use `Tabs` — never manual `aria-selected` management
- **Popovers**: Use `Popover` — never absolute-positioned `<div>` with manual show/hide
- **Accordions**: Use `Accordion` or `Collapsible` — never manual height animation

Why: Radix handles keyboard navigation, focus trapping, ARIA attributes, and screen reader announcements correctly by construction. Hand-rolling these is error-prone and violates accessibility rules.

## Design Token File Format

When a project uses design tokens, the source of truth is W3C DTCG format:

```json
{
  "$type": "color",
  "brand": {
    "primary": { "$value": "#3b82f6", "$description": "Primary brand color" },
    "secondary": { "$value": "#10b981", "$description": "Secondary accent" }
  }
}
```

Tokens are transformed to Tailwind `@theme` CSS variables via Style Dictionary or manual mapping:

```css
@theme {
  --color-brand-primary: #3b82f6;
  --color-brand-secondary: #10b981;
}
```

## Component File Structure

Every component file should follow this structure:

```
imports (React, primitives, utilities, types)
  |
type definitions (props interface)
  |
component definition (forwardRef when needed)
  |
variants (if using cva/class-variance-authority)
  |
export
```

- Co-locate component variants using `cva()` from class-variance-authority
- Export both the component and its props type
- Keep component files under 200 lines (enforced by components.md)

## Figma-to-Code Pipeline

When a Figma design is available:

1. **Read the design** via Figma MCP server — inspect layers, styles, spacing, and component structure
2. **Map to existing components** — identify which shadcn/ui components match the design
3. **Extract tokens** — pull colors, typography, spacing from the Figma file into the token system
4. **Generate components** — use Magic UI MCP or manual implementation
5. **Verify** — compare generated output against the Figma design visually

Never generate components from a text description when a Figma design exists.

## Quality Checks

Before marking any frontend component as complete:

- [ ] All colors, spacing, radii, and typography use tokens (no hardcoded values)
- [ ] Interactive elements use Radix primitives (no hand-rolled accessibility)
- [ ] Component exists in registry OR follows shadcn conventions
- [ ] Loading, error, and empty states are handled
- [ ] Responsive at mobile (375px), tablet (768px), and desktop (1280px)
- [ ] Keyboard navigable (Tab, Enter, Escape, Arrow keys where applicable)
- [ ] Color contrast meets WCAG 2.1 AA (4.5:1 text, 3:1 large text)
