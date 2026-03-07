# Test Rules
# Applies to: **/*.test.*, **/*.spec.*, **/tests/**, **/__tests__/**

- Name tests descriptively: "should [expected behavior] when [condition]".
- Follow the AAA pattern: Arrange (setup), Act (execute), Assert (verify).
- One assertion concept per test. Multiple asserts are fine if they verify one behaviour.
- Tests must be independent. Never rely on execution order or shared mutable state.
- Clean up after each test. Reset databases, clear mocks, remove temp files.
- Mock at boundaries (network, filesystem, database), not internal functions.
- Never mock the thing you are testing.
- Test edge cases: empty input, null/undefined, boundary values, error paths.
- Test file naming: `[module].test.[ext]` or `[module].spec.[ext]`.
- Keep test files next to the code they test, or in a parallel __tests__ directory.
- Never skip tests without a linked ticket explaining why.
- Flaky tests must be fixed immediately or quarantined with a ticket.
