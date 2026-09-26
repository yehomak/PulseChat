---
disable-model-invocation: true
description: Stress-test a plan or requirement before writing any code — interview-ready clarification
---

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled. Ask the whole frontier in one round, numbered, with your recommended answer. Wait before the next round.

Format each round:
```
❓ Q1 - <title>: <question>
➡️ <recommended answer>

---

❓ Q2 - <title>: <question>
➡️ <recommended answer>
```

For a Rails interview feature, always ask the frontier in this order if not already settled:

**Round 1 — Scope:**
- What is the feature boundary? (which models, which controllers, which UI)
- Is this synchronous (return in the HTTP response) or async (job + broadcast)?
- What happens on failure? (retry, silent discard, user error message)

**Round 2 — Scale:**
- Is this on the hot path (~4,000 req/sec) or background?
- Does it need real-time delivery to the client? (→ ActionCable broadcast)
- Any N+1 risk? (has_many associations loaded in a loop)

**Round 3 — Security:**
- Is data scoped to the current user? (`Current.user.model.find` vs `Model.find`)
- Any mass-assignment risk? (new params keys)
- Any broadcast that could leak to other users? (scope to `Current.user`)

Done when the frontier is empty — every assumption explicit. Do not write code until confirmed.
