# Load test

How PulseChat's message pipeline behaves under load, what limited it, and what changed.

**Result:** the bottleneck was Sidekiq concurrency, not the web tier or the database. Raising
concurrency from 5 to 20 took the 1,000-job drain from 215s to 57s, and a sustained 15 msg/s
load went from a growing 713-job backlog to zero. Capping LLM history at 50 messages removed a
17% throughput penalty on long conversations.

---

## Setup

| | |
|---|---|
| Machine | Apple M1, 8 cores, 16 GB |
| Services | PostgreSQL 16.15, Redis 8.8.0, all local |
| Rails | development env, `RAILS_LOG_LEVEL=warn` (debug SQL logging skews latency) |
| Puma | 5 threads (`RAILS_MAX_THREADS=5`) |
| LLM | mocked by `LlmClient` (`LLM_MOCK=1`): fixed 1,000 ms sleep plus a canned reply |

The mock keeps runs free and repeatable, and a fixed latency makes the queueing behaviour easy
to reason about. Real providers have variable latency, so treat absolute numbers as a model of
the system, not a production forecast.

### Scenarios

| Script | What it measures |
|---|---|
| `script/load/pipeline.rb` `SCENARIO=spread` | Worker throughput: 100 users × 10 pending messages enqueued at once |
| `script/load/pipeline.rb` `SCENARIO=history` | `build_history` cost: 50 users whose conversations already hold `SIZE` messages |
| `script/load/http.js` (k6) | Request path: rate limiter → token row lock → insert → enqueue, 100 rotating users |

The pipeline script bypasses HTTP so worker-side limits are isolated. Latency is
`updated_at − created_at` of the user message: time from enqueue to completion, queue wait
included.

---

## Baseline (Sidekiq concurrency 5, DB pool 5)

| Scenario | Throughput | Latency p50 / p95 |
|---|---|---|
| Spread, 1,000 jobs | 4.66 jobs/s | 108 s / 204 s |
| History, 0 prior messages | 4.60 jobs/s | 6.6 s / 10.9 s |
| History, 1,000 prior | 4.64 jobs/s | 6.4 s / 10.7 s |
| History, 10,000 prior | **3.86 jobs/s** | 7.4 s / 12.6 s |
| Spread, concurrency 10, pool 5 | 9.10 jobs/s | 56 s / 104 s |
| Spread, concurrency 25, pool 5 | 21.58 jobs/s | 24 s / 44 s |
| HTTP, 15 req/s, 1,139 requests | 0 failed | **19 ms / 23 ms** (p99 27 ms) |

After the HTTP run, **713 jobs were still queued**. Zero errors and zero
`ConnectionTimeoutError` across every run.

### Findings

**1. Throughput ≈ concurrency ÷ LLM latency.** Five threads with a 1 s LLM can finish about
5 jobs/s, and the spread run reached 4.66 (93%). The sweep scaled almost linearly to 25 threads.
The HTTP run shows the consequence: the app accepted 15 msg/s but answered about 4.7, so the
queue grew by about 10/s and every reply arrived later than the one before. Required
concurrency follows Little's law: arrival rate × latency = 15 × 1 s = 15 threads, plus headroom.

**2. The DB pool was not a constraint. My hypothesis was wrong.** I expected
`ConnectionTimeoutError` above 5 threads, but 25 threads on a 5-connection pool ran clean.
Sampling `pg_stat_activity` during that run showed at most 5 Sidekiq connections, and almost
always 0 active. Since Rails 7.2, Active Record returns a connection to the pool after each
query outside a transaction, so a job holds no connection during its 1 s LLM call. The pool
would only matter if a transaction were held open across the call.

**3. `build_history` loaded the whole conversation.** With no measurable cost at 1,000
messages but −17% throughput at 10,000, the cost is linear in history length. The bigger issue
is correctness: 10,000 messages exceed any LLM context window, so a real call would fail or
bill for context that gets truncated.

**4. The request path is healthy.** p95 of 23 ms at 15 req/s with zero errors: the Redis
limiter, the `FOR UPDATE` token deduction and the insert are not bottlenecks at this load.
A separate over-limit run (20 users, 30 req/s) returned exactly 10 × 200 per user and 429 for
everything else, so the limiter holds under concurrent requests.

---

## Changes

| Commit | Change | Why |
|---|---|---|
| `perf(sidekiq)` | Concurrency 5 → 20; the DB pool now follows Sidekiq's concurrency (web keeps Puma's thread count) | Finding 1. The pool change is a safeguard, not a fix (finding 2) |
| `perf(jobs)` | `build_history` sends the 50 most recent messages, oldest first | Finding 3 |

## After

| Scenario | Before | After |
|---|---|---|
| Spread: throughput | 4.66 jobs/s | **17.43 jobs/s** (3.7×) |
| Spread: drain time / p95 wait | 214.7 s / 204 s | **57.4 s / 55 s** |
| History 10,000, concurrency 5 | 3.86 jobs/s | **4.65 jobs/s**, same as an empty conversation (4.59) |
| HTTP 15 req/s: backlog at end | 713 jobs | **0** |
| HTTP p95 / p99 | 23 / 27 ms | 22 / 27 ms |

The capped history query is a backward index scan on `[conversation_id, created_at]` that reads
50 rows, at 0.075 ms on a 10,000-message conversation:

```
Limit (actual time=0.016..0.062 rows=50)
  -> Index Scan Backward using index_messages_on_conversation_id_and_created_at on messages
       Index Cond: (conversation_id = 798)
Execution Time: 0.075 ms
```

At 20 threads the spread run reached 87% of the theoretical 20 jobs/s, compared with 93% at
5 threads. That gap is thread contention inside one Ruby process. Past this point, add Sidekiq
processes rather than threads.

---

## Known issues (not fixed here)

- **The rate limiter counts rejected requests.** `RateLimiter#allowed?` runs `ZADD` before
  checking the count, so a client that keeps retrying while limited keeps its window full and
  stays blocked. Found by reading the code, not measured. The fix is to check before adding,
  atomically in a Lua script.
- **In production, capacity is set by the LLM, not by the app.** With real latency of 3–5 s,
  the same 15 msg/s needs 45–75 concurrent calls. That makes the provider's concurrency and
  rate limits the ceiling, and it's where the planned load balancer across LLM servers fits.

## Pitfalls hit while building the harness

- **A long-running Homebrew Redis answered blocking commands late.** `BRPOP key 1` took
  3–5 s on the instance that had run for days, against 1.0 s on a fresh one, so Sidekiq's idle
  fetches timed out and picked up jobs seconds late. `brew services restart redis` fixed it.
  Worth ruling out before trusting any Sidekiq latency number locally.
- **`rails runner` enables the query cache.** A polling loop kept reading the first result, so
  the script never saw jobs finish. `pipeline.rb` runs inside `ActiveRecord::Base.uncached`.
- **Logins are rate-limited per IP** (10 per 3 minutes), so the HTTP setup creates sessions
  directly and signs the cookie with the app's key instead of posting to `/session`.

---

## Reproduce

Terminal 1, Sidekiq with the mock (concurrency defaults to 20; override with `SIDEKIQ_CONCURRENCY`):

```bash
LLM_MOCK=1 LLM_MOCK_LATENCY_MS=1000 RAILS_LOG_LEVEL=warn bundle exec sidekiq
```

Terminal 2, pipeline scenarios:

```bash
export RAILS_LOG_LEVEL=warn
SCENARIO=spread  USERS=100 PER_USER=10 bin/rails runner script/load/pipeline.rb
SCENARIO=history USERS=50  SIZE=10000  bin/rails runner script/load/pipeline.rb
```

HTTP scenario (needs Puma running, and k6 from `brew install k6`):

```bash
RAILS_LOG_LEVEL=warn bin/rails server                          # terminal 3
USERS=100 bin/rails runner script/load/http_setup.rb           # writes tmp/load/users.json
RATE=15 RAMP=30s HOLD=60s k6 run script/load/http.js
```

The scripts only touch users whose email starts with `load_` and wipe them at the start of each
run.

**Real-LLM guard.** Before seeding or enqueueing anything, both `pipeline.rb` and
`http_setup.rb` check every Sidekiq process serving the `llm` queue. A worker in mock mode
advertises the `llm-mock` label (`config/initializers/sidekiq.rb`, visible in
`Sidekiq::ProcessSet`). If any worker lacks it, the script aborts with zero jobs enqueued, so a
Sidekiq started with `.env` sourced can't turn a load test into thousands of billed calls. The
check runs on the worker's actual state, not the script's environment, which is what matters
because the worker is the process that calls the LLM. As a second line, `pipeline.rb` also
verifies that the replies are the mock's. `LLM_MOCK` is ignored in production.
