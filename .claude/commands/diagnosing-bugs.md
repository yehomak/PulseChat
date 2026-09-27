---
allowed-tools: Bash(bin/rails *), Bash(bundle exec *), Bash(grep:*), Bash(tail:*), Read
description: Structured 6-phase debug loop for Rails — no hypothesis without a red-capable test first
---

# Diagnosing Bugs — Rails

A discipline for hard bugs. Never jump to a hypothesis without a feedback loop.

## Phase 1: Build a feedback loop

The most important phase. Build a **tight, red-capable, deterministic** loop:

1. **Failing test** — `bin/rails test test/path_to_test.rb` targeting the exact symptom
2. **Request replay** — `curl` or a Rails integration test reproducing the exact HTTP sequence
3. **Console script** — `bin/rails runner scripts/repro.rb` with minimal reproduction
4. **Log scan** — `tail -f log/development.log | grep ERROR` for exception traces

For Sidekiq job bugs specifically:
```ruby
# In test: perform inline to remove async uncertainty
perform_enqueued_jobs { trigger_the_action }
```

For ActionCable/Turbo bugs:
```bash
tail -f log/development.log | grep -E "ActionCable|Turbo|broadcast"
```

Completion: one command you've already run, that goes **red on this bug**, is deterministic, and runs in < 10 seconds.

## Phase 2: Reproduce + minimise

Shrink the repro to the smallest scenario still going red. Remove models, params, callbacks one at a time.

## Phase 3: Hypothesise

3–5 ranked hypotheses before testing any. Each must be falsifiable:
> "If X is the cause, then changing Y will make it green."

Rails-common hypotheses to consider first:
- **`*_commit` race:** callback firing before transaction commits (Sidekiq reads before record exists)
- **N+1:** association loaded in a loop, strict_loading raises
- **Scope missing:** `Model.find` not scoped to `Current.user`
- **Queue:** job on wrong queue, starved behind ML inference jobs
- **Broadcast scope:** ActionCable broadcasting to all subscribers instead of scoped channel

## Phase 4: Instrument

One variable at a time. Tag every debug log `[DEBUG-xxxx]` for easy cleanup.

## Phase 5: Fix + regression test

Write the failing test first, then fix, then watch it go green.

## Phase 6: Cleanup

Remove all `[DEBUG-xxxx]` logs. Re-run the original repro. Done.
