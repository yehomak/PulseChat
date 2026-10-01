# PulseChat

> A Rails 8 monolith: users send messages in a conversation; rate-limited via a Redis sliding window, tokens deducted under a PostgreSQL row lock, content moderated, and the LLM reply generated async by Sidekiq and streamed live via ActionCable + Turbo Streams.

## Tech Stack
- Ruby 3.4.4 (`.ruby-version`), Rails 8.1.4 (monolith)
- PostgreSQL, Redis, Sidekiq 8
- Hotwire (Turbo Streams + Stimulus), ActionCable (Redis adapter in dev, SolidCable in prod), Propshaft, Tailwind
- LLM: Groq's OpenAI-compatible API via the `ruby-openai` gem, wrapped in `LlmClient`; key in `XAI_API_KEY`
- **No** AnyCable, **no** PgBouncer, **no** read replicas, **no** pgvector

## Code Conventions & Standards
1. **Rails 8 Idioms**: Use `params.expect` for strong parameters instead of `params.require`.
2. **Controller/Service Layer**: Keep controllers thin. Delegate domain logic to service objects under `app/services/`.
3. **Background Jobs (Sidekiq)**:
   - Jobs are thin: load the record, call a service, own retries. The operation lives in the service.
   - Always pass primitive arguments (e.g., `message.id`). Never pass ActiveRecord model instances.
   - ActiveJob `retry_on` is the only retry layer (`sidekiq_options retry: 0`). Retry transient errors only (5xx, timeouts, 429, deadlocks); `discard_on` everything else. Mark a record failed only once retries are exhausted.
   - Idempotency: services return early on `message.finished?`; multi-row writes go in one transaction.
4. **Concurrency & Locking**:
   - Use `User.lock("FOR UPDATE")` or atomic SQL updates for sensitive mutations (like token counts).
   - Redis read-check-write goes in a Lua script (`RateLimiter::SCRIPT`), not `MULTI`: record only after the check passes.
5. **Real-time UI**:
   - Broadcast with `Turbo::StreamsChannel.broadcast_replace_to` / `broadcast_append_to`, **after** the transaction commits.
   - Use `<%= turbo_stream_from ... %>` in view templates.
6. **Database & Indexing**:
   - Explicitly define composite indexes for sorted queries (e.g., `[:conversation_id, :created_at]`).
   - Use partial indexes where applicable (e.g., `where: "active = TRUE"`).

## Domain Models

| Model | Key associations | Notable callbacks |
|---|---|---|
| User | `has_many :conversations`, `has_many :sessions` | — |
| Conversation | `belongs_to :user`, `has_many :messages` | — |
| Message | `belongs_to :conversation` | — (broadcasts come from `ChatReplyService`, not the model) |
| Session | `belongs_to :user` | — |
| Current | `CurrentAttributes`: holds `:session`, delegates `.user` | n/a |

**Enums on Message** (integers are stored; never renumber, a test pins the mapping):
- `role`: `user_message: 0`, `assistant: 1` (prefix: `role_`)
- `status`: `pending: 0`, `streaming: 1`, `completed: 2`, `failed: 3`, `cancelled: 4`, `blocked: 5` (prefix: `status_`)

`Message#finished?` is the single list of terminal states (completed, failed, cancelled, blocked). Use it rather than chaining status checks.

## Background Jobs

| Job | Queue | Triggered by | Does |
|---|---|---|---|
| `LlmInferenceJob` | `:llm` | `MessagesController#create` via `perform_later` | `ChatReplyService.call(message)`; retries transient errors, fails the message otherwise |

`config/sidekiq.yml`: concurrency 20 (override with `SIDEKIQ_CONCURRENCY`), queues `llm` then `default`. In Sidekiq processes the DB pool follows concurrency (`config/database.yml`). Start with `bundle exec sidekiq`.

## Real-time delivery

No custom channels. `conversations/show` subscribes with `turbo_stream_from @conversation`, which uses Turbo's `Turbo::StreamsChannel` with a **signed** stream name: only a page rendered for a user who can see the conversation gets a valid signature. `ApplicationCable::Connection` authenticates the WebSocket (`identified_by :current_user`, rejects anonymous connections).

Broadcasts are issued from `ChatReplyService` (reply, blocked) and `LlmInferenceJob` (failed status) on the `conversation` record. Add a custom channel only for client→server messages (for example typing indicators).

## Services

| Service | Responsibility | Key detail |
|---|---|---|
| `ChatReplyService` | Produce the reply to a user message | Moderation guard → history (last 50, blocked turns excluded) → `LlmClient` → persist → broadcast |
| `ContentModerator` | Keyword guard for sexual content involving minors | One precompiled whole-word, case-insensitive regex; everyday words ("child", "minor") deliberately excluded |
| `LlmClient` | Provider transport | `LLM_MOCK=1` returns a canned reply (ignored in production); mocked Sidekiq workers advertise the `llm-mock` label |
| `RateLimiter` | Redis sliding window, 10 req / 60 s | Lua script; key `rate:<user_id>`; rejected attempts are not recorded |
| `TokenLedger` | Deduct tokens under PG row lock | `User.lock("FOR UPDATE")` inside `transaction`; raises `InsufficientTokens` |

**Moderation placement:** the guard lives in `ChatReplyService`, which owns producing a reply, before history is loaded and before the LLM call. Not in the controller (other reply paths would bypass it) and not in `LlmClient` (transport). Blocked messages still cost tokens, since the charge happens in the controller.

## Auth

Rails 8 built-in: `Session` model + `has_secure_password` on `User`. `Current.session` → `Current.user` set in `ApplicationController` via a `before_action`. Passwords controller handles reset tokens. Logins are rate-limited to 10 per 3 minutes per IP.

## Testing
- Prefer concise Rails Minitest integration/unit tests for core models, services and jobs.
- Stub the LLM with `LlmClient.stub(:chat, ...)`; never call the provider from tests.
- Tests use Redis DB 2 (+ worker index when parallel) and flush it before each test; `test_helper.rb` refuses to flush DB 0 or 1 (development).
- For guards (transactions, terminal checks, filters), prove the test fails with the guard removed.

## Load testing
See `docs/load_test.md`. Scripts in `script/load/` only touch `load_*` users and refuse to run unless every `llm` Sidekiq worker is mocked (`LLM_MOCK=1`). Never run them against a worker started with `.env` sourced.

## Claude Code tooling

Read `.claude/conventions.md` before creating or placing any file.

**Commands:** `/commit` `/pr` `/migrate` `/grilling` `/diagnosing-bugs` `/wait-what` `/handoff`

**Agents:** `rails-reviewer` · `job-agent` · `turbo-agent` · `query-agent`

**Hooks (automatic):** rubocop-gate on Stop · frozen-string-literal on Write · callback-lint on Write · n1-detector after test runs · migration-guard on destructive DB commands · secret-scan on Write

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

## Git Workflow

Branch naming: `feature/`, `fix/`, `perf/` or `chore/` + `<short-desc>`. Never commit directly to main. PRs are squash-merged.

```bash
git checkout -b feature/<task-slug>
```

Create the branch before writing any code. After finishing each logical layer (migration, model, service, controller, job, view), remind the user to run `/commit` before moving to the next layer. Do not batch layers into one commit. Rebase one branch at a time on a clean working tree.

## Running Locally

```bash
bin/setup          # install deps + create + migrate DB
bin/dev            # Puma + Tailwind watcher + Sidekiq (foreman loads .env: real LLM calls)
LLM_MOCK=1 bin/dev # same, with mocked LLM replies
bin/rails test     # must be green before touching feature code
```

## Quick Fixes

```bash
brew services start redis && redis-cli ping          # Redis down
brew services restart redis                          # Sidekiq fetch timeouts / late job pickup (stale Redis timers)
brew services start postgresql@16 && pg_isready      # PG down
bin/rails db:migrate && bin/rails db:test:prepare    # pending migrations
bundle exec sidekiq                                  # start Sidekiq (reads config/sidekiq.yml)
bundle add bullet --group "development,test"         # add N+1 detector
```

## Probe Checklist (answer before writing code)

- [ ] Which layer owns this concern? Put the guard in the owner, right before the irreversible step
- [ ] Sync or async? → if async: `after_create_commit`, not `after_create`
- [ ] Shared mutable row? → `SELECT FOR UPDATE` inside `transaction`
- [ ] Broadcasts? → scope to `Current.user`-owned record, never flat string key; send after commit
- [ ] N+1 risk? → `includes` plan before writing any query
- [ ] New index? → `algorithm: :concurrently` + `disable_ddl_transaction!`
- [ ] Transient vs terminal errors in jobs? → `retry_on` transient, `discard_on` terminal
- [ ] Does filtered or blocked data leak through a later path (history, exports, logs)?

## Open Questions

- Refund tokens for blocked messages? Needs the charged amount stored on the message.
- Moderation is keyword-only; a classifier would catch misspellings and paraphrase.
