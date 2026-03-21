---
name: ui-scaffold
description: >
  Scaffold a frontend project with shadcn/ui + Tailwind v4 + design tokens.
  Use when starting a new app, adding a frontend to an existing project, or
  when asked to "scaffold UI", "set up frontend", "init design system",
  "create app", or "bootstrap project". Supports SaaS, dashboard, and
  landing page templates.
---

# UI Scaffold

Scaffold a production-ready frontend with a complete design system in one shot.

## Parameters

| Parameter | Default | Options |
|-----------|---------|---------|
| **Template** | `dashboard` | `saas`, `dashboard`, `landing`, `minimal` |
| **Framework** | `next` | `next`, `sveltekit`, `nuxt`, `astro` |
| **Brand** | _(optional)_ | Brand name, colors, or Figma URL |
| **PRD** | _(optional)_ | Path to PRD file for context-aware scaffolding |

If the user says "scaffold a dashboard app", start immediately with defaults.
Only ask clarifying questions if the request is ambiguous about template type.

## Workflow

```
1. Assess       Determine template, framework, and brand context
2. Scaffold     Create project structure with chosen template
3. Design       Generate design tokens from brand brief or defaults
4. Components   Install shadcn/ui and configure presets
5. Verify       Run dev server and confirm it builds
```

### 1. Assess

Determine what the user needs:

- **Template selection**: Match the user's request to a template:
  - `saas` — Auth, billing, dashboard, landing page, marketing pages (reference: next-forge)
  - `dashboard` — Admin panel with sidebar nav, data tables, charts, forms (reference: next-shadcn-dashboard-starter)
  - `landing` — Marketing landing page with hero, features, pricing, CTA
  - `minimal` — Bare shadcn/ui + Tailwind v4 setup, no pages

- **Brand context**: If the user provides:
  - A Figma URL → use Figma MCP to extract colors, typography, spacing
  - Brand colors → map to token system
  - A PRD → extract brand/design requirements from it
  - Nothing → use a distinctive default palette (NOT purple-on-white)

### 2. Scaffold

Create the project structure based on framework choice.

#### Next.js (default)

```bash
# Create Next.js project with TypeScript, Tailwind, App Router
npx create-next-app@latest {{project-name}} --typescript --tailwind --app --eslint --src-dir --import-alias "@/*"
cd {{project-name}}
```

#### SvelteKit

```bash
npx sv create {{project-name}} --template minimal --types ts
cd {{project-name}}
npm install -D tailwindcss @tailwindcss/vite
```

### 3. Design Tokens

Generate a design token file based on brand context. Create `tokens/design-tokens.json` in W3C DTCG format:

```json
{
  "color": {
    "$type": "color",
    "brand": {
      "primary": { "$value": "{extracted or generated}", "$description": "Primary brand color" },
      "secondary": { "$value": "{extracted or generated}", "$description": "Secondary accent" },
      "accent": { "$value": "{extracted or generated}", "$description": "Call-to-action accent" }
    },
    "neutral": {
      "50": { "$value": "#fafafa" },
      "100": { "$value": "#f5f5f5" },
      "200": { "$value": "#e5e5e5" },
      "300": { "$value": "#d4d4d4" },
      "400": { "$value": "#a3a3a3" },
      "500": { "$value": "#737373" },
      "600": { "$value": "#525252" },
      "700": { "$value": "#404040" },
      "800": { "$value": "#262626" },
      "900": { "$value": "#171717" },
      "950": { "$value": "#0a0a0a" }
    },
    "semantic": {
      "success": { "$value": "#22c55e" },
      "warning": { "$value": "#f59e0b" },
      "error": { "$value": "#ef4444" },
      "info": { "$value": "#3b82f6" }
    }
  },
  "spacing": {
    "$type": "dimension",
    "xs": { "$value": "0.25rem" },
    "sm": { "$value": "0.5rem" },
    "md": { "$value": "1rem" },
    "lg": { "$value": "1.5rem" },
    "xl": { "$value": "2rem" },
    "2xl": { "$value": "3rem" },
    "3xl": { "$value": "4rem" }
  },
  "radius": {
    "$type": "dimension",
    "sm": { "$value": "0.25rem" },
    "md": { "$value": "0.375rem" },
    "lg": { "$value": "0.5rem" },
    "xl": { "$value": "0.75rem" },
    "full": { "$value": "9999px" }
  },
  "typography": {
    "$type": "fontFamily",
    "display": { "$value": "'{chosen display font}', serif", "$description": "Headlines and hero text" },
    "body": { "$value": "'{chosen body font}', sans-serif", "$description": "Body text and UI" },
    "mono": { "$value": "'JetBrains Mono', monospace", "$description": "Code blocks" }
  }
}
```

**Font selection**: Follow `frontend-design.md` rules — choose distinctive, characterful fonts.
Never default to Inter, Roboto, Arial, or system fonts for display text.
Pair a distinctive display font with a clean body font. Examples:
- Editorial: Playfair Display + Source Sans 3
- Technical: Space Mono + DM Sans
- Luxury: Cormorant Garamond + Outfit
- Playful: Fredoka + Nunito
- Brutalist: Anton + Work Sans

### 4. Install shadcn/ui

```bash
# Initialize shadcn with Tailwind v4
npx shadcn@latest init

# Install base components for the chosen template
```

#### Components by template

**Dashboard**:
```bash
npx shadcn@latest add button card input label table tabs dialog dropdown-menu \
  sheet sidebar avatar badge separator skeleton toast tooltip \
  select checkbox command popover calendar
```

**SaaS**:
```bash
npx shadcn@latest add button card input label form dialog sheet \
  avatar badge separator skeleton toast navigation-menu \
  accordion tabs dropdown-menu
```

**Landing**:
```bash
npx shadcn@latest add button card badge separator navigation-menu \
  accordion sheet
```

**Minimal**:
```bash
npx shadcn@latest add button card input label
```

### 5. Apply Design Tokens to Tailwind

Map the DTCG tokens to Tailwind v4's `@theme` directive in the project's global CSS:

```css
@import "tailwindcss";

@theme {
  /* Brand colors from tokens */
  --color-brand-primary: var(--token-color-brand-primary);
  --color-brand-secondary: var(--token-color-brand-secondary);
  --color-brand-accent: var(--token-color-brand-accent);

  /* Map to shadcn semantic colors */
  --color-primary: var(--color-brand-primary);
  --color-secondary: var(--color-brand-secondary);
  --color-accent: var(--color-brand-accent);

  /* Typography */
  --font-display: var(--token-font-display);
  --font-body: var(--token-font-body);
  --font-mono: var(--token-font-mono);

  /* Radii */
  --radius-sm: var(--token-radius-sm);
  --radius-md: var(--token-radius-md);
  --radius-lg: var(--token-radius-lg);
}
```

### 6. Generate Template Pages

Based on the template, generate the initial page structure:

**Dashboard**: Sidebar layout, overview page with stats cards, data table page, settings page
**SaaS**: Landing page, auth pages (login/register), dashboard shell, pricing page
**Landing**: Hero section, features grid, testimonials, pricing table, CTA footer
**Minimal**: Single page with component showcase

### 7. Verify

```bash
npm run dev
# Confirm: no build errors, pages render, design tokens apply correctly
```

If the project has a Figma design, use agent-browser to screenshot the running app
and visually compare against the design.

## Post-Scaffold

After scaffolding, remind the user:

1. **Figma MCP** is available — connect a Figma design to refine components (`FIGMA_API_KEY` required)
2. **Magic UI MCP** generates additional components from prompts (`MAGIC_UI_API_KEY` required)
3. **shadcn MCP** helps discover registry components during development
4. **Design tokens** are in `tokens/design-tokens.json` — edit there, not in CSS directly
5. The project follows HCF rules: `design-system.md`, `components.md`, `frontend-design.md`

## Font Loading

Always set up proper font loading. For Next.js:

```tsx
// app/layout.tsx
import { Playfair_Display, Source_Sans_3 } from 'next/font/google'

const display = Playfair_Display({ subsets: ['latin'], variable: '--font-display' })
const body = Source_Sans_3({ subsets: ['latin'], variable: '--font-body' })

export default function RootLayout({ children }) {
  return (
    <html className={`${display.variable} ${body.variable}`}>
      <body>{children}</body>
    </html>
  )
}
```

## Notes

- This skill creates the scaffold only — feature implementation follows normal ralph.sh workflow
- Design tokens are the source of truth; Tailwind theme is a derived output
- The scaffold includes HCF rules automatically via the project's `.claude/` directory
- For AI-native apps (copilot UI, streaming responses), consider adding Vercel AI SDK and CopilotKit post-scaffold
