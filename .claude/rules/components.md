# UI Component Rules
# Applies to: **/components/**, **/pages/**, **/layouts/**, **/views/**, **/*.tsx, **/*.jsx, **/*.vue, **/*.svelte

- Type all props explicitly. Never use `any` for prop types.
- Every interactive element must be keyboard accessible.
- Every image must have an alt attribute. Decorative images use alt="".
- Use semantic HTML elements (button, nav, main, section) over generic divs.
- Handle loading, error, and empty states for every data-dependent component.
- Never put business logic in components. Extract to hooks, services, or utilities.
- Keep components under 200 lines. Split when larger.
- Use responsive design. Test at mobile, tablet, and desktop breakpoints.
- Never hardcode colours, spacing, or font sizes. Use design tokens or theme variables.
- Ensure sufficient colour contrast (WCAG 2.1 AA: 4.5:1 for text, 3:1 for large text).
- Label all form inputs. Never rely on placeholder text as the only label.
- Test components in isolation before integrating.
