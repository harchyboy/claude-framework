# Database Rules
# Applies to: **/migrations/**, **/db/**, **/schema/**, **/seeds/**, **/models/**

- Never write destructive migrations (DROP TABLE, DROP COLUMN) without explicit human approval.
- Always make migrations reversible — include both up and down operations.
- Add indexes for columns used in WHERE, JOIN, and ORDER BY clauses.
- Never use SELECT * in application code. Select only the columns you need.
- Use parameterized queries or an ORM. Never concatenate user input into SQL.
- Wrap multi-step data changes in transactions.
- Name migrations with timestamps and descriptive names (e.g., 20240301_add_user_email_index).
- Test migrations against a copy of production-like data before applying.
- Add NOT NULL constraints by default. Only allow NULL when there is an explicit reason.
- Consider query performance: avoid N+1 queries, use JOINs or batch loading.
- Document schema decisions in an ADR when changing data models.
- Never store secrets, tokens, or passwords in plain text. Use hashing or encryption.
