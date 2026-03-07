# API Routes Rules
# Applies to: **/api/**, **/routes/**, **/controllers/**, **/handlers/**

- Use RESTful conventions: GET for reads, POST for creates, PUT/PATCH for updates, DELETE for deletes.
- Return appropriate HTTP status codes: 200 OK, 201 Created, 400 Bad Request, 401 Unauthorized, 403 Forbidden, 404 Not Found, 500 Internal Server Error.
- Validate all request input at the handler boundary. Never trust client data.
- Return consistent error response shape: `{ error: { code, message, details? } }`.
- Never expose internal error details (stack traces, SQL errors) in production responses.
- Use middleware for cross-cutting concerns: auth, rate limiting, logging.
- Rate limiting: consider per-endpoint limits for expensive operations.
- Always handle async errors — wrap route handlers in try/catch or use error middleware.
- Never return more data than the client needs. Select specific fields.
- Log request metadata (method, path, status, duration) but never log request bodies containing credentials or PII.
- Use pagination for list endpoints. Never return unbounded result sets.
- Version APIs when breaking changes are unavoidable.
