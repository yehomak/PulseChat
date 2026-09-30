# PulseChat

A practice Rails 8 monolith demonstrating a high-concurrency, real-time AI messaging pipeline. Users send messages in a conversation; the request is rate-limited via a Redis sliding window, token balance is deducted atomically under a PostgreSQL row-level lock, and an LLM reply is generated asynchronously by Sidekiq and streamed live to the browser over ActionCable via Turbo Streams.

---

## Pipeline

```
[Browser Client]
     │ (1) POST /conversations/:id/messages
     ▼
[MessagesController] ──(2) Check Rate Limit?──► [Redis ZSET Sliding Window]
     │ (Allowed)
     ├──(3) Check / Deduct Tokens?──────────► [PostgreSQL FOR UPDATE Lock]
     │
     ├──(4) Create Message (status: :pending)
     │
     └──(5) Enqueue LlmInferenceJob ─────► [Sidekiq Queue]
                                                  │
                                            (Worker Executes)
                                                  │
                                                  ├──► Call LLM (LlmClient)
                                                  │
                                                  └──► Broadcast Turbo Stream
                                                             │
                                                             ▼
                                                     [ActionCable / Redis]
                                                             │
                                                             ▼
                                                     [Live UI Append]
```

---

## Stack

| Layer | Choice |
|---|---|
| Runtime | Ruby 3.4.4 / Rails 8.1.4 |
| Database | PostgreSQL |
| Background jobs | Sidekiq 8 (Redis-backed) |
| Real-time | ActionCable (Redis adapter) + Turbo Streams |
| Rate limiting | Redis ZSET sliding window |
| Token ledger | PostgreSQL `SELECT … FOR UPDATE` |
| AI | Groq, OpenAI-compatible API via `ruby-openai` (`LlmClient`) |
| Frontend | Hotwire (Turbo + Stimulus) + Tailwind CSS |
| Assets | Propshaft + importmap |

---

## Prerequisites

- Ruby 3.4.4 (see `.ruby-version`)
- PostgreSQL 15+
- Redis 7+

---

## Setup

```bash
bin/setup
```

That script will install dependencies, create and migrate the database, and seed a demo user.

---

## Running locally

```bash
bin/dev          # starts Puma + Sidekiq + Tailwind watcher via Foreman/Overmind
```

Environment variables (copy `.env.example` → `.env`):

| Variable | Purpose |
|---|---|
| `XAI_API_KEY` | API key for the Groq endpoint |
| `LLM_MOCK` / `LLM_MOCK_LATENCY_MS` | Replace the LLM with a fixed-latency canned reply (ignored in production) |
| `SIDEKIQ_CONCURRENCY` | Sidekiq threads, default 20; the DB pool follows it |
| `REDIS_URL` | Redis connection (default: `redis://localhost:6379/0`) |
| `DATABASE_URL` | PostgreSQL connection string |

---

## Load testing

Under a mocked 1 s LLM, raising Sidekiq concurrency from 5 to 20 cut a 1,000-job drain from
215 s to 57 s and cleared a 713-job backlog at 15 msg/s. Capping LLM history at 50 messages
removed a 17% throughput penalty on 10,000-message conversations. The request path held p95
23 ms throughout.

Method, full results, what turned out wrong, and how to reproduce: [docs/load_test.md](docs/load_test.md).

---

## Tests

```bash
bin/rails test
```

---

## Key source locations

| Concern | Path |
|---|---|
| Rate limiter | `app/services/rate_limiter.rb` |
| Token ledger | `app/services/token_ledger.rb` |
| LLM inference job | `app/jobs/llm_inference_job.rb` |
| LLM client (+ mock) | `app/services/llm_client.rb` |
| Load test scripts | `script/load/` |
| Conversations channel | `app/channels/conversations_channel.rb` |
| Messages controller | `app/controllers/messages_controller.rb` |
