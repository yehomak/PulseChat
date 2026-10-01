---
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

For a Rails interview feature, ask the whole frontier in one round. Every question must be answered before writing code.

**Scope**
- What is the feature boundary? (models, controllers, UI)
- Sync (HTTP response) or async (job + broadcast)?
- What happens on failure? (retry, discard, user error)

**Scale & real-time**
- Hot path (~4,000 req/sec) or background?
- Real-time delivery to client? → ActionCable broadcast
- N+1 risk? → `includes` plan before writing any query

**Concurrency & atomicity**
- Shared mutable state? (same row or Redis key under concurrent requests)
- Read-modify-write? → `SELECT FOR UPDATE` or Redis atomic op (`MULTI`/`INCR`)
- Two simultaneous requests — what breaks? (double-deduction, duplicate record, double-enqueue)
- Read immediately after this write? → primary only, not replica

**Security**
- Data scoped to `Current.user`? (`Current.user.resource.find` not `Resource.find`)
- Broadcast that could leak? → scope to `Current.user`-owned record, never a flat string key

Done when the frontier is empty — every assumption explicit. Do not write code until confirmed.

## Final output — design rationale, then implementation plan

After all rounds are settled, output both blocks without being asked:

### Block 1 — Design rationale

For each non-obvious decision settled during grilling, explain:
- What you chose
- The one most likely alternative
- Why you rejected it in one sentence

Format:
```
**<Decision title>:** Chose <X> over <Y> — <reason tied to this system's constraints>.
```

Only include decisions where the alternative was genuinely viable. Skip obvious choices.

Examples:
```
**Rate limit storage:** Chose Redis ZSET over DB counter — DB counter can't do sliding window without a full table scan per request on the hot path.
**Enqueue timing:** Chose after_create_commit over after_create — after_create fires inside the open transaction; the worker would find the record missing under load.
**Broadcast scope:** Chose stream scoped to current_user over conversation ID — conversation ID allows any authenticated subscriber to receive another user's events.
```

This is what you say out loud in the interview when the interviewer asks "why did you do it this way?"

### Block 2 — Implementation plan

After all rounds are settled, output this without being asked:

```
## Implementation plan

**Branch:** `feature/<slug>`
**Sync/async:** <sync returns in response / async via Sidekiq>
**Queue:** <queue name and why — fast vs slow>
**DB writes:** <primary only / primary + replica read>
**Broadcast:** <none / Turbo Stream scoped to Current.user via AnyCable>
**Idempotency:** <status field guard / unique index / none needed>
**Concurrency risk:** <none / SELECT FOR UPDATE / Redis lock — reason>
**Indexes needed:** <list with algorithm: :concurrently if table has data>

**Layer order (commit after each one — run `/commit` before moving to the next):**
1. migration
2. model
3. <service if logic is complex>
4. controller
5. <job if async>
6. <view/partial if UI changes>

**Test cases to write (fill these in concretely based on what grilling settled):**

For each item below, write the specific scenario name — not a generic placeholder. These become the actual test method names when it's time to write tests.

- [ ] Happy path: `test "<action> with valid input does <expected result>"`
- [ ] Auth scope: `test "cannot <action> on another user's <resource>"` → expect 404
- [ ] Failure / error path: `test "<action> when <condition> returns <status> and does not <side effect>"`
- [ ] Idempotency (if job or write): `test "<action> twice produces same result as once"`
- [ ] Race condition (if shared mutable state settled in Round 2): `test "concurrent <action> on same <resource> does not <bad outcome>"`
- [ ] Boundary (if rate limit or counter): `test "<action> at limit is allowed"` + `test "<action> at limit+1 is blocked"` + `test "<action> after window resets is allowed"`
- [ ] N+1 (if associations loaded): `test "<action> does not N+1 on <association>"` — use `assert_queries`
- [ ] Status/state transition (if status field): `test "<action> failure sets status to <state> and does not create <record>"`

Only include rows that apply — skip ones grilling ruled out. A test list with 3 concrete cases is better than 8 generic ones.
```

Say: "Does this plan look right before I start coding?"
