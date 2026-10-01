# PulseChat

A Rails 8 monolith for real-time AI chat: users message an LLM companion, replies are generated
asynchronously and streamed live, with rate limiting, a token ledger, content moderation and
load-tested capacity.

## What this demonstrates

- **Concurrency-safe money-like state:** token deduction under a PostgreSQL row lock; a Redis
  sliding-window rate limiter in one atomic Lua script ([#10](https://github.com/yehomak/PulseChat/pull/10))
- **Async LLM pipeline:** a thin Sidekiq job over `ChatReplyService`, retrying only transient
  provider errors ([#11](https://github.com/yehomak/PulseChat/pull/11)), with cancel mid-generation
- **Moderation:** blocked before the LLM call and kept out of later context
  ([#9](https://github.com/yehomak/PulseChat/pull/9))
- **Measured capacity:** a k6 and Sidekiq load harness found the real bottleneck; 1,000-job drain
  215 s → 57 s ([#8](https://github.com/yehomak/PulseChat/pull/8), [report](docs/load_test.md))
- **Real-time UI:** Turbo Streams over ActionCable, no custom JavaScript for message delivery

## Quick start

Needs Ruby 3.4.4, PostgreSQL 15+ and Redis 7+. No API key required.

```bash
cp .env.example .env         # mocked LLM replies by default
bin/setup --skip-server      # install gems, create + seed the database
bin/dev                      # Puma + Sidekiq + Tailwind on http://localhost:3000
```

Log in as **demo@pulsechat.dev / pulsechat-demo** (seeded in development only). Try a normal
message, press Stop while it generates, or send `write a story about a jailbait girl` to see
moderation. For real replies, set `XAI_API_KEY` (a Groq key) in `.env` and remove `LLM_MOCK`.

```bash
bin/rails test               # 68 tests; Redis isolated per worker, never your dev DB
```

## Pipeline

```
Browser ── POST /conversations/:id/messages
   │
   ▼
MessagesController
   ├── RateLimiter ─────────── Redis Lua: evict · count · record only if allowed → 429
   ├── TokenLedger ─────────── PostgreSQL SELECT … FOR UPDATE → 402
   ├── Message (pending)
   └── LlmInferenceJob ─────── Sidekiq, queue :llm, concurrency 20
          │                     retry_on transient (5xx, timeout, 429) · discard the rest
          ▼
      ChatReplyService
          ├── finished? ─────── idempotent on retry / cancel
          ├── ContentModerator ─ blocked → mark blocked + apology, in one transaction
          ├── history ───────── last 50 messages, blocked turns excluded
          ├── LlmClient ─────── Groq (or mock)
          ├── cancelled? ────── Redis signal or DB status → drop the reply
          └── persist → broadcast after commit → Turbo Stream → live UI
```

## Design decisions

| Decision | Why |
|---|---|
| Moderation lives in `ChatReplyService`, before history and the LLM call | The service owns producing a reply. A controller check would be skipped by any other reply path; `LlmClient` is transport only |
| Blocked turns are excluded from later history | Otherwise the next clean message sends the blocked text to the provider ("continue the story above") |
| Thin job, logic in a service | Retry and queue policy stay in the job, the reply operation in one reusable, testable place |
| Retry only transient errors; fail the message after retries | A bad key shouldn't retry, and a timeout shouldn't kill the reply. ActiveJob is the single retry layer |
| Rate limiter as a Lua script, not `MULTI` | The check has to happen before the write, so rejected attempts don't fill the window |
| `blocked` as a status value, not a boolean | A message ends in exactly one state; `Message#finished?` is the one list of terminal states |
| Sidekiq concurrency 20, sized by measurement | Throughput ≈ threads ÷ LLM latency; needed ≈ arrival rate × latency (Little's law) |

## What I got wrong or caught

- **DB pool exhaustion never happened.** I expected it above 5 threads; 25 threads on a 5-connection
  pool ran clean, because Rails returns connections between queries and a job holds none during the
  LLM call. The load test disproved the guess before I "fixed" it ([report](docs/load_test.md)).
- **Moderation leaked through history.** The first version blocked the turn, but the next message
  still sent the blocked text to the provider. Caught in manual testing; fixed and pinned by a test.
- **`retry_on` was dead code.** The job marked messages failed before retrying, and failed is
  terminal, so no retry ever ran. Found while reviewing the moderation work.
- **The rate limiter counted rejected requests**, keeping a retrying client blocked indefinitely.

Each fix ships with a test that fails when the fix is removed.

## How it was built

Built with [Claude Code](https://claude.com/claude-code), using the project setup in
[`.claude/`](.claude) and [`CLAUDE.md`](CLAUDE.md). The AI wrote most of the code; design
decisions, and the call on what to measure and what to fix, were mine.

- **`/grilling` before code:** every feature starts as a design tree of questions (placement,
  atomicity, failure modes) settled before implementation
- **One layer per commit:** migration → model → service → job → view, each reviewed by a
  `rails-reviewer` agent before committing
- **Guards are mutation-checked:** remove the transaction, filter or check, and confirm a test fails
- **Hooks enforce the basics:** RuboCop when the agent stops, secret scanning on every file write,
  and a guard against destructive database commands
- **The load test refuses to run against a worker that would call the real LLM,** so no load run can
  turn into billed calls

## Stack

| Layer | Choice |
|---|---|
| Runtime | Ruby 3.4.4 / Rails 8.1.4 |
| Database | PostgreSQL |
| Background jobs | Sidekiq 8 (`config/sidekiq.yml`, concurrency 20) |
| Real-time | ActionCable (Redis adapter) + Turbo Streams |
| Rate limiting | Redis sliding window (Lua) |
| Token ledger | PostgreSQL `SELECT … FOR UPDATE` |
| Moderation | Keyword guard (`ContentModerator`) |
| AI | Groq, OpenAI-compatible API via `ruby-openai` (`LlmClient`, mockable) |
| Frontend | Hotwire (Turbo + Stimulus) + Tailwind CSS, Propshaft + importmap |

## Environment

| Variable | Purpose |
|---|---|
| `LLM_MOCK` / `LLM_MOCK_LATENCY_MS` | Canned replies with fixed latency (ignored in production) |
| `XAI_API_KEY` | Groq API key, for real replies |
| `SIDEKIQ_CONCURRENCY` | Sidekiq threads, default 20; the DB pool follows it |
| `REDIS_URL` / `DATABASE_URL` | Only if not on localhost defaults |

## Key source locations

| Concern | Path |
|---|---|
| Reply operation + moderation guard | `app/services/chat_reply_service.rb` |
| Moderation terms | `app/services/content_moderator.rb` |
| LLM client (+ mock) | `app/services/llm_client.rb` |
| Rate limiter | `app/services/rate_limiter.rb` |
| Token ledger | `app/services/token_ledger.rb` |
| Job, retry policy | `app/jobs/llm_inference_job.rb` |
| Messages controller | `app/controllers/messages_controller.rb` |
| Load test | `script/load/`, [`docs/load_test.md`](docs/load_test.md) |
