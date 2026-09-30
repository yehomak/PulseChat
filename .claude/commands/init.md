---
allowed-tools: Read, Bash, Write
description: Generate a CLAUDE.md for a freshly cloned Rails repo with no existing project context
---

You are orienting yourself in a cloned Rails repo you have never seen. Generate a `CLAUDE.md` that gives every future agent enough context to work without asking questions.

## Step 0 — Verify the environment is ready

Run these checks first and report results. For any failure, print the fix command — do not just report the failure.

```bash
bundle check 2>/dev/null || echo "NEEDS: bundle install"
redis-cli ping 2>/dev/null || echo "FAIL: Redis not running"
pg_isready 2>/dev/null || echo "FAIL: PostgreSQL not running"
bin/rails db:migrate:status 2>/dev/null | grep " down " | head -5
bin/rails test 2>&1 | tail -3
grep -q "bullet" Gemfile && echo "Bullet: present" || echo "Bullet: MISSING"
```

Report status and the exact fix for each failure:

| Problem | Fix |
|---|---|
| `bundle check` fails | `bundle install` |
| Redis not running | `brew services start redis` — verify with `redis-cli ping` → PONG |
| PostgreSQL not running | `brew services start postgresql@16` (adjust version) — verify with `pg_isready` |
| Migrations pending (shows `down`) | `bin/rails db:migrate` |
| Tests failing on clean repo | `bin/rails db:test:prepare` then `bin/rails test` |
| schema.rb out of sync | `bin/rails db:schema:dump` |
| Bullet missing | `bundle add bullet --group "development,test"` then add to `config/environments/test.rb`: `Bullet.enable = true; Bullet.rails_logger = true` inside `config.after_initialize` |
| Yarn/JS deps missing | `yarn install` (only if repo has `package.json`) |
| Sidekiq needed for feature | `bundle exec sidekiq -q default` (adjust queues from `config/sidekiq.yml`) |

Do not proceed past Step 0 with any service down or migrations pending. A broken baseline wastes the entire session.

---

## Step 1 — Read the repo

Run these with the Bash tool (in parallel where possible), read whatever exists:

```bash
cat Gemfile
cat db/schema.rb
bin/rails routes 2>/dev/null | head -60
ls app/models/
ls app/jobs/ 2>/dev/null
ls app/channels/ 2>/dev/null
ls app/controllers/
cat config/sidekiq.yml 2>/dev/null
cat config/cable.yml 2>/dev/null
git log --oneline -10
cat README.md 2>/dev/null | head -60
redis-cli ping 2>/dev/null || echo "Redis: DOWN"
bin/rails db:migrate:status 2>/dev/null | tail -10
```

Read the 3–5 most central model files in full to understand associations and callbacks.

## Step 2 — Build a profile

From your read, extract:

- **Ruby / Rails version** (from Gemfile)
- **Key gems** — Sidekiq, Devise vs built-in auth, Hotwire, AnyCable vs ActionCable, pgvector, Bullet, Brakeman, RuboCop vs StandardRB, PgBouncer indicators
- **Domain models** — list each with its key associations and any notable callbacks
- **Background jobs** — list each with its queue name and priority order (from `config/sidekiq.yml`)
- **ActionCable / AnyCable channels** — list each, what it streams, and whether AnyCable is configured
- **Auth pattern** — Devise / built-in Session model / other
- **Test framework** — Minitest vs RSpec
- **Read replicas** — check `config/database.yml` for `connects_to` or multiple database configs
- **PgBouncer** — check `database.yml` for `prepared_statements: false` (signals PgBouncer in transaction mode; affects advisory locks and session-scoped features)
- **pgvector** — check schema for `vector` columns or `neighbor` gem in Gemfile
- **Redis usage** — distinguish between Rails.cache (one connection) vs $redis / direct Redis client (another); note any key namespacing patterns
- **Queue priority** — list queues in priority order from `config/sidekiq.yml`; note any dedicated queues for ML/inference vs fast jobs

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

**Hooks (automatic):** rubocop-gate (Stop) · frozen-string-literal (Write) · callback-lint (Write) · n1-detector (after test) · migration-guard (destructive DB commands)

**Agent invocation rules — follow these without being asked:**

| When | Invoke |
|---|---|
| Before writing any job file | `job-agent` |
| Before any broadcast or ActionCable code | `turbo-agent` |
| After finishing any layer (model / service / controller / job) | `rails-reviewer` |
| n1-detector warns after a test run | `query-agent` |
| Tests red after one fix attempt | `Skill("diagnosing-bugs")` |
| Need a migration | `Skill("migrate", args: "<description>")` |

**User-only commands (suggest, do not invoke):** `/commit` · `/pr` · `/handoff`

## Git workflow

Branch naming: `feature/<short-desc>` or `fix/<short-desc>`. Never commit directly to main.

```bash
git checkout -b feature/<task-slug>
```

Create the branch before writing any code. Commit after each logical layer (migration, model, service, controller, job). See `.claude/conventions.md` for commit message format.

## Running locally

```bash
bin/setup       # install deps + create + migrate DB
bin/dev         # starts Puma + Tailwind watcher (+ Sidekiq if in Procfile.dev)
bin/rails test  # must be green before touching any feature code
```

## Quick fixes (run these if something is broken)

```bash
# Redis not running
brew services start redis
redis-cli ping                          # → PONG

# PostgreSQL not running
brew services start postgresql@16       # adjust version
pg_isready                              # → accepting connections

# Pending migrations
bin/rails db:migrate
bin/rails db:test:prepare               # sync test DB after migrate

# Bundler out of sync
bundle install

# JS deps missing
yarn install

# schema.rb out of sync with migrations
bin/rails db:schema:dump

# Start Sidekiq manually (if not in Procfile.dev)
bundle exec sidekiq -q llm -q default  # adjust queues from config/sidekiq.yml

# Bullet not in Gemfile (add for N+1 detection)
bundle add bullet --group "development,test"
# then in config/environments/test.rb:
# config.after_initialize { Bullet.enable = true; Bullet.rails_logger = true }

# Tests fail on clean clone
bin/rails db:drop db:create db:migrate db:test:prepare
bin/rails test
```

## Scale context (EverAI production)

**Default assumption: high volume.** Design for ~4,600 req/sec unless Juan explicitly says otherwise. Never ask "what's the expected volume?" — assume the worst case and design accordingly: Redis not DB on hot path, async not sync, explicit queue not default.

| Constraint | Value | Implication for this session |
|---|---|---|
| Peak req/sec | ~4,600 | No DB on hot path — Redis or in-memory only |
| Sidekiq jobs/sec | ~520 | Queue priority is load-bearing; slow jobs starve fast ones |
| PostgreSQL | 1.81TB + read replicas | Concurrent indexes mandatory; can't read replica immediately after write |
| PgBouncer | Transaction mode | No advisory locks, no `SET LOCAL`, no `LISTEN/NOTIFY` |
| WebSockets | AnyCable (Go layer) | Broadcasts: Rails → Redis pub/sub → Go → client |
| LLM | Self-hosted, streaming | Token-by-token broadcast; batched PG writes; dedicated queue |

## Probe checklist (answer these before writing any code)

- [ ] Sync or async? → if async: `after_create_commit`, not `after_create`
- [ ] Shared mutable row? → `SELECT FOR UPDATE` inside `transaction` (not advisory lock — PgBouncer)
- [ ] Broadcasts? → scope to `Current.user`, never a flat string key
- [ ] N+1 risk? → `includes` plan before writing any query
- [ ] New index? → `algorithm: :concurrently` + `disable_ddl_transaction!`
- [ ] Transient vs terminal errors in jobs? → separate rescue clauses

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

## Step 5 — Handoff prompt

Print exactly this line after Step 4.5:

> "When you receive the feature task, paste the full description into this chat and run `/grilling`. Do not write any code before that."
