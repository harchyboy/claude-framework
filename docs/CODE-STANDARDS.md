# Code Standards — Hartz Claude Framework

> These standards apply to ALL code written by Claude Code, Ralph Moss, and agent teams.
> Patterns here are derived from recurring P1/P2 review findings. Follow them during
> implementation — do not wait for review to catch violations.

---

## 1. Security

### Auth transport
- **NEVER send secrets in request bodies.** Always use HTTP headers (e.g. `X-Modal-Secret`, `Authorization`).
- Body content appears in request logs, error responses, and proxy caches. Headers are stripped by default.
- If a codebase has both GET and POST endpoints, use the **same auth mechanism** for both.

### Input validation
- Validate and cap size/count on any user-supplied data forwarded to external services (file uploads, arrays, text fields).
- Validate filenames against an allowlist pattern server-side, not just client-side.
- Every `deepMerge` or object spread from user input must skip `__proto__`, `constructor`, and `prototype` keys.

### Path traversal
- Every function that accepts a slug, filename, or path segment must validate it before use.
- Use `path.resolve()` + `startsWith(baseDir + sep)` (Node) or `Path.resolve().is_relative_to()` (Python 3.9+).
- Apply validation at every boundary — never rely on a single layer.

### Error messages
- Never reveal internal configuration state in error responses (e.g. "secret not configured").
- Return generic "Forbidden" for all auth failures. Log specifics server-side only.

---

## 2. TypeScript

### Response handling
- **Every `fetch().then(r => r.json())` call:** check `resp.ok` before parsing.
- **Every `resp.json()` result:** assign to `unknown` first, then narrow with a type guard or validation.
- **Never cast directly** from `resp.json()` to a typed interface (`as MyType`). The response shape is not guaranteed.

```typescript
// BAD — unchecked cast from any
const data = await resp.json() as MyResponse

// GOOD — check status, then validate
if (!resp.ok) return { error: `HTTP ${resp.status}` }
const raw: unknown = await resp.json()
if (!isMyResponse(raw)) return { error: 'Invalid response shape' }
```

### Type guards
- A type guard claiming `v is T` must validate **all required fields** of `T`, not just a subset.
- If you only check 3 fields of a 20-field interface, name the guard `isMinimalT` and document what it actually checks.
- Type guards used before writes are especially critical — they're the last line of defence against persisting corrupt data.

### Request body validation
- Always check `typeof body !== 'object' || body === null || Array.isArray(body)` before casting request bodies.
- A JSON array is valid JSON but not a valid request object — reject it explicitly.

### Error contracts
- Functions in the same module must use a **consistent error contract**: all throw, or all return typed error unions.
- Never mix throwing and returning `null` in sibling functions — callers won't know which to expect.

### Casts
- `as unknown as T` is a red flag. If you need a double cast, the types are wrong — fix the source.
- `as T` after a type guard is redundant — the guard already narrowed the type.

---

## 3. Accessibility (WCAG 2.1 AA)

### Form fields
- Every `<input>`, `<textarea>`, and `<select>` must have a matching `<label htmlFor="id">` / `id` pair.
- Dynamic inputs (e.g. in a list) need `aria-label` with descriptive text including position context.
- Helper text (format hints, constraints) must be linked via `aria-describedby`.

### ARIA tab pattern
When using `role="tablist"` / `role="tab"`, you must implement the **complete** pattern:
- Each tab needs: `id`, `role="tab"`, `aria-selected`, `aria-controls="{panelId}"`
- Each panel needs: `role="tabpanel"`, `id`, `aria-labelledby="{tabId}"`
- Arrow keys (Left/Right) must move between tabs
- Tab key must move focus into the active panel, not to the next tab
- **Never declare tab roles without the full structure** — incomplete ARIA is worse than no ARIA.

### Focus management
- `focus:outline-none` must **always** be paired with a visible replacement: `focus-visible:ring-2 focus-visible:ring-{colour}`.
- Buttons without `focus:border-*` or `focus-visible:ring-*` are invisible to keyboard users.
- When a modal closes, focus must return to the trigger element. Store a ref to the trigger before opening.

### Live regions
- `aria-live="polite"` containers must be **always mounted** in the DOM, not conditionally rendered.
- Content injected into a freshly mounted live region may not be announced. Mount the region once, update its contents.

### Colour
- Never convey meaning with colour alone. Add visually-hidden text summaries, icons, or patterns.
- Decorative SVGs need `aria-hidden="true"`.

---

## 4. Data Integrity

### Atomic writes
- Use the tmp-file-then-rename pattern (`os.replace` in Python, `fs.rename` in Node) for all file writes.
- **Always clean up .tmp files** — add a cleanup pass or wrap in try/finally.
- On network filesystems (Modal Volume, NFS): atomicity only holds within a single commit/flush boundary. Document this.
- Define the atomic write helper **once** and call it everywhere. Never duplicate the pattern inline.

### Distributed locks
- Check-then-set is not a lock. Modal Dict, Redis GET+SET, and filesystem checks are all vulnerable to TOCTOU races.
- If you cannot get true CAS (compare-and-swap), document that the "lock" is best-effort and ensure the operation is **idempotent** as the real guard.
- All locks must have a **TTL or staleness check**. A lock without expiry becomes permanent on process crash.

### Write fallbacks
- When a write function tries local filesystem first, then falls back to a remote store, distinguish `ENOENT` (file/dir not found — correct to fall through) from write errors (disk full, permissions — should propagate as failure).
- A silent fallback on all errors creates split-brain: writes go to remote, reads come from local.

### Validation before persistence
- Validate data **immediately before writing**, not just at the API boundary.
- For config updates: verify the merged result matches the expected schema AND that identity fields (slug, id) match the route parameters.

---

## 5. API Design

### HTTP status codes
- `200` — success, full response
- `207` — partial success (some operations succeeded, some failed) — document what failed
- `400` — malformed request (bad JSON, missing fields)
- `401` — not authenticated
- `403` — authenticated but not authorised
- `404` — resource not found
- `409` — conflict (resource already exists)
- `422` — validation failed (valid JSON but business rules reject it)
- `502` — upstream service error (Modal, external API)
- `503` — service not configured

### Consistency
- All endpoints in the same module should use the same auth pattern, error shape, and response format.
- If GET endpoints use header auth and POST endpoints use body auth, unify them.

---

## 6. Python (Modal / FastAPI)

### Endpoint auth
- Use FastAPI's `Annotated[str, Header()]` for header-based auth on all endpoints.
- Define **one** auth helper and use it everywhere. Don't maintain separate helpers for GET vs POST.

### File I/O on Modal Volume
- Always call `ml_volume.reload()` before reads to get the latest state.
- Always call `ml_volume.commit()` after writes to persist changes.
- Use `_atomic_write_json()` (or equivalent helper) for all JSON writes. Never open-write-close directly.
- Clean up `.tmp` files in any initialisation or setup function.

### Modal Dict
- Modal Dict is a key-value store, not a database. It has no transactions, no CAS, no TTL.
- Use it for job status tracking and metadata. Do not use it as a distributed lock without documenting the race window.

---

## 7. Performance

### File I/O
- When reading multiple independent files, use `Promise.all` (Node) or `ThreadPoolExecutor` (Python) — not sequential loops.
- For directory listings that grow unbounded, add pagination (limit/offset) or maintain an index file.

### Network calls
- Fan out independent HTTP requests with `Promise.all`, not sequential `await`.
- Always set timeouts on external HTTP calls.
- Check `resp.ok` before parsing — a non-2xx with an HTML error page will throw on `.json()`.

---

## Checklist (use before every commit)

- [ ] All `fetch()` calls check `resp.ok` before `.json()`
- [ ] No secrets in request bodies — headers only
- [ ] All form fields have label associations (`htmlFor`/`id` or `aria-label`)
- [ ] No `focus:outline-none` without `focus-visible:ring-*` replacement
- [ ] Type guards validate all fields they claim to narrow
- [ ] `deepMerge` / object spreads from user input skip prototype keys
- [ ] Atomic writes use tmp+rename pattern with cleanup
- [ ] File reads from user input have path traversal guards
- [ ] Error messages don't leak internal configuration state
- [ ] Parallel I/O used for independent file/network operations
