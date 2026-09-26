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
                                                  ├──► Call Anthropic API
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
| Runtime | Ruby 3.4.9 / Rails 8.1.3 |
| Database | PostgreSQL + pgvector |
| Background jobs | Sidekiq 8 (Redis-backed) |
| Real-time | ActionCable (Redis adapter) + Turbo Streams |
| Rate limiting | Redis ZSET sliding window |
| Token ledger | PostgreSQL `SELECT … FOR UPDATE` |
| AI | Anthropic Claude (via `anthropic` gem) |
| Frontend | Hotwire (Turbo + Stimulus) + Tailwind CSS |
| Assets | Propshaft + importmap |

---

## Prerequisites

- Ruby 3.4.9
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
| `ANTHROPIC_API_KEY` | Anthropic API key for LLM inference |
| `REDIS_URL` | Redis connection (default: `redis://localhost:6379/0`) |
| `DATABASE_URL` | PostgreSQL connection string |

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
| Conversations channel | `app/channels/conversations_channel.rb` |
| Messages controller | `app/controllers/messages_controller.rb` |
