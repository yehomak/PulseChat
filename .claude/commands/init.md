---
allowed-tools: Read, Bash, Write
description: Generate a CLAUDE.md for a freshly cloned Rails repo with no existing project context
---

You are orienting yourself in a cloned Rails repo you have never seen. Generate a `CLAUDE.md` that gives every future agent enough context to work without asking questions.

## Step 1 — Read the repo

Run these in parallel, read whatever exists:

```
!`cat Gemfile`
!`cat db/schema.rb`
!`bin/rails routes 2>/dev/null | head -60`
!`ls app/models/`
!`ls app/jobs/ 2>/dev/null`
!`ls app/channels/ 2>/dev/null`
!`ls app/controllers/`
!`cat config/sidekiq.yml 2>/dev/null`
!`cat config/cable.yml 2>/dev/null`
!`git log --oneline -10`
!`cat README.md 2>/dev/null | head -60`
!`redis-cli ping 2>/dev/null || echo "Redis: DOWN"`
!`bin/rails db:migrate:status 2>/dev/null | tail -10`
```

Read the 3–5 most central model files in full to understand associations and callbacks.

## Step 2 — Build a profile

From your read, extract:

- **Ruby / Rails version** (from Gemfile)
- **Key gems** — Sidekiq, Devise vs built-in auth, Hotwire, AnyCable, pgvector, Bullet, Brakeman, RuboCop vs StandardRB
- **Domain models** — list each with its key associations and any notable callbacks
- **Background jobs** — list each with its queue and what triggers it
- **ActionCable channels** — list each and what it streams
- **Auth pattern** — Devise / built-in Session model / other
- **Test framework** — Minitest vs RSpec

## Step 3 — Write CLAUDE.md

Write the file to the repo root. Use exactly this structure:

```markdown
# <Project name from README or directory>

<One sentence describing what the app does, inferred from models and routes.>

## Stack

- Ruby <version>, Rails <version>
- PostgreSQL<, pgvector if present>
- Redis + Sidekiq<, or Solid Queue if present>
- Hotwire (Turbo + Stimulus) + ActionCable<, AnyCable if present>
- <any other notable gems>

## Domain models

| Model | Key associations | Notable callbacks |
|---|---|---|
| User | has_many :conversations | — |
| ... | ... | ... |

List every model. For callbacks, note any `*_commit` hooks and what they enqueue/broadcast.

## Background jobs

| Job | Queue | Triggered by |
|---|---|---|
| MessageBroadcastJob | default | Message after_create_commit |
| ... | ... | ... |

## ActionCable channels

| Channel | Streams | Auth check |
|---|---|---|
| MessagesChannel | conversation | current_user present? |

## Auth

<Describe the auth pattern: Session model + has_secure_password / Devise / other.>
<Note how current_user is set — ApplicationController concern, Current attributes, etc.>

## Conventions

- `.claude/conventions.md` — file placement, section order, commit format. Read before creating any file.
- Controllers: thin, REST-only, always scope finders to `Current.user`
- Callbacks: lambda syntax only, `*_commit` for any async work
- Jobs: `_later`/`_now` pattern, shallow wrappers, explicit queue
- Params: `params.expect` (Rails 8+)

## Claude Code tooling

**Commands:** `/commit` `/pr` `/migrate` `/grilling` `/diagnosing-bugs` `/wait-what` `/handoff`

**Agents:** `rails-reviewer` · `job-agent` · `turbo-agent` · `query-agent`

**Hooks (automatic):** rubocop-gate (Stop) · frozen-string-literal (Write) · callback-lint (Write) · n1-detector (after test) · migration-guard (destructive DB commands)

## Running locally

```bash
bin/setup
bin/dev
bin/rails test
```

## Open questions

<List anything you could not determine from the code — auth approach unclear, queue names unknown, etc. The developer should fill these in during the first 15 minutes with the interviewer.>
```

## Step 4 — Confirm

Print: "CLAUDE.md written. Open questions to clarify with the interviewer: [list them]."

## Step 4.5 — Suggest starting pattern

Based on what you found in the codebase, recommend which architectural pattern the first task is most likely to involve:

- **Pattern A — SELECT FOR UPDATE** — token/credit mutation, any counter that must not double-decrement under concurrent requests. Signal: `credits`, `tokens`, `balance` columns; multiple workers hitting the same user row.
- **Pattern B — Redis ZSET sliding window** — high-volume per-user rate limiting (e.g. messages per minute). Signal: rate limit logic in controllers or jobs, `$redis` references, `ZREMRANGEBYSCORE` comments.
- **Pattern C — Idempotent job + Turbo broadcast** — LLM inference job with real-time result delivery. Signal: LLM/AI job + ActionCable channel + `after_create_commit` broadcast pattern.
- **Pattern D — SKIP LOCKED** — queue worker deduplication, ensuring only one worker processes a given record. Signal: multiple Sidekiq workers + shared DB queue table.
- **Pattern E — Atomic SQL + unique index** — idempotent billing or credit deduction, prevent double-spend. Signal: unique index on a transaction table, `insert_or_ignore` / `upsert` usage.

State which pattern fits and why in one sentence. If unclear, list the two most likely and what to ask the interviewer to confirm.

Do not start implementing anything. This command is orientation only.
