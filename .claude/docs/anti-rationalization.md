# Anti-rationalization Rules

These are the exact excuses Claude uses to skip steps. None of them are valid.

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. The test takes 30 seconds to write. |
| "I'll add tests later" | You won't. Tests written after the fact prove nothing. |
| "The user didn't ask for tests" | CODE-STANDARDS.md requires them. The user hired a professional. |
| "I'll fix it in a follow-up" | Follow-ups don't happen. Fix it now or document it as a known issue. |
| "It's obvious what this does" | It's obvious to you today. It won't be in 3 months. |
| "The code is self-documenting" | PROGRESS.md updates are not documentation — they're coordination. Update them. |
| "I've completed the task" | Did you run the code? Did you see the output? Claiming completion without verification is hallucination. |
| "That's outside the scope" | If it breaks, it's in scope. If it's a security risk, it's in scope. |
| "The existing code doesn't do this" | The existing code is why we're here. Raise your standard. |
| "I'm following the spirit of the rules" | Violating the letter of the rules IS violating the spirit. Follow them exactly. |

Violating these rules is not a style preference — it is a quality failure.
