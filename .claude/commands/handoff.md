---
disable-model-invocation: true
argument-hint: "what the next session will focus on"
description: Compact this conversation into a handoff doc for the next session
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the OS temp directory (`/tmp/everai-handoff-TIMESTAMP.md`).

Include:
- What was built or investigated this session
- Current state: what works, what's broken, what's in progress
- Key Rails patterns applied (which `*_commit` rules, which queue decisions, any migration state)
- Open questions or blocked items
- Suggested skills for the next session: `/grilling` if requirements still fuzzy, `/diagnosing-bugs` if something is broken, `/tdd` if writing tests next

Do not duplicate content already in commits or test output — reference file paths instead.
Redact any API keys or credentials.

If `$ARGUMENTS` provided, treat it as the focus of the next session and tailor accordingly.
