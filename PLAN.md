# PulseChat — Implementation Plan

Branch: `agent/task1-llm-pipeline`

---

## Phase 0 — Dependencies & Config

- [ ] Uncomment `bcrypt` in Gemfile; add `gem "ruby-openai"`
- [ ] Switch ActionCable adapter in `config/cable.yml` → Redis (development + production)
- [ ] Configure Sidekiq initializer (`config/initializers/sidekiq.rb`) with Redis URL
- [ ] Add `XAI_API_KEY`, `REDIS_URL` to credentials / `.env.example`

---

## Phase 1 — Database

### Migrations (run in order)

| # | File | Creates |
|---|---|---|
| 1 | `create_users` | `users` — email, password_digest, token_balance (integer, default 10_000) |
| 2 | `create_conversations` | `conversations` — user_id FK, title string |
| 3 | `create_messages` | `messages` — conversation_id FK, role (user/assistant), content text, status integer (pending/streaming/completed/failed), tokens_used integer |
| 4 | `add_indexes` | composite `(conversation_id, created_at)` on messages; index on `conversations.user_id` |

### Schema notes
- `messages.status` is an integer-backed enum; default `0` (pending).
- `users.token_balance` must never go below 0 — enforced at the DB level with a check constraint and at the app level inside a `FOR UPDATE` lock.

---

## Phase 2 — Models

### `User`
- `has_secure_password`
- `has_many :conversations, dependent: :destroy`
- validates email uniqueness/format
- No direct `has_many :messages` — always go through conversation

### `Conversation`
- `belongs_to :user`
- `has_many :messages, dependent: :destroy`
- `scope :recent`

### `Message`
- `belongs_to :conversation`
- `enum :status, { pending: 0, streaming: 1, completed: 2, failed: 3 }`
- `enum :role, { user_message: 0, assistant: 1 }`
- validates content presence
- `scope :ordered, -> { order(:created_at) }`
- Callback: `after_create_commit` → no async broadcast here; broadcasting is the job's job

---

## Phase 3 — Services

### `RateLimiter` (`app/services/rate_limiter.rb`)

Sliding-window algorithm using a Redis ZSET.

```
key   = "rate:#{user_id}"
score = now (epoch ms)
window = 60 seconds, limit = 10 requests
```

API:
```ruby
RateLimiter.new(user_id: id).allowed?   # returns true/false
```

Internals (wrapped in `redis.multi`):
1. `ZREMRANGEBYSCORE key 0 (now - window_ms)`  — evict old entries
2. `ZCARD key`                                  — count current
3. If count < limit: `ZADD key score member`; `EXPIRE key window`; return true
4. Else: return false

### `TokenLedger` (`app/services/token_ledger.rb`)

Atomic deduction with PostgreSQL row lock.

API:
```ruby
TokenLedger.new(user_id: id).deduct!(amount)
# raises TokenLedger::InsufficientTokens if balance < amount
# returns remaining balance
```

Internals:
```ruby
User.transaction do
  user = User.lock("FOR UPDATE").find(user_id)
  raise InsufficientTokens if user.token_balance < amount
  user.update_columns(token_balance: user.token_balance - amount)
end
```

---

## Phase 4 — Controller

### `SessionsController`
Simple email/password login; sets `session[:user_id]`.

### `ConversationsController`
`index`, `show` — scoped to `Current.user`.

### `MessagesController`

`POST /conversations/:conversation_id/messages`

```
1. rate_limiter = RateLimiter.new(user_id: current_user.id)
   → 429 if not allowed

2. cost = estimate_token_cost(params[:content])  # rough: content.length / 4
   TokenLedger.new(...).deduct!(cost)
   → 402 if insufficient

3. message = conversation.messages.create!(role: :user_message, content: ..., status: :pending)

4. LlmInferenceJob.perform_async(message.id)

5. respond_to { turbo_stream → render pending message partial; html → redirect }
```

Error responses: both turbo_stream and html formats return appropriate flash/stream.

---

## Phase 5 — Job

### `LlmInferenceJob` (`app/jobs/llm_inference_job.rb`)

```ruby
sidekiq_options queue: :llm, retry: 3
```

`perform(message_id)`:
1. `return if message.completed?`  — idempotency guard
2. `message.update!(status: :streaming)`
3. Build conversation history from prior messages
4. Call Grok via `OpenAI::Client.new(access_token: ENV["XAI_API_KEY"], uri_base: "https://api.x.ai/v1").chat(...)` with model `grok-3-mini`
5. Create assistant `Message` with `role: :assistant`, `status: :completed`, `tokens_used: response.usage.output_tokens`
6. Broadcast both messages via `Turbo::StreamsChannel.broadcast_append_to`

Broadcast targets:
- `"conversation_#{conversation_id}"` stream
- Partial: `messages/_message`

---

## Phase 6 — ActionCable Channel

### `ConversationsChannel` (`app/channels/conversations_channel.rb`)

```ruby
def subscribed
  conversation = current_user.conversations.find(params[:conversation_id])
  stream_for conversation
end
```

Auth guard: reject if `current_user.nil?`.

---

## Phase 7 — Views

### Layout additions
- Turbo + Stimulus tags already in `application.html.erb`
- Add `<%= action_cable_meta_tag %>` to `<head>`

### `conversations/show.html.erb`
```erb
<%= turbo_stream_from @conversation %>

<div id="messages">
  <%= render @messages %>
</div>

<%= render "messages/form", conversation: @conversation %>
```

### `messages/_message.html.erb`
```erb
<div id="<%= dom_id(message) %>" class="...">
  <span class="role"><%= message.role %></span>
  <p><%= message.content %></p>
  <% if message.status_pending? %>
    <span class="animate-pulse">Thinking…</span>
  <% end %>
</div>
```

### `messages/create.turbo_stream.erb`
```erb
<%= turbo_stream.append "messages", partial: "messages/message", locals: { message: @message } %>
```

---

## Phase 8 — Tests

| File | What it covers |
|---|---|
| `test/models/message_test.rb` | validations, enum values |
| `test/models/user_test.rb` | password auth, token balance |
| `test/services/rate_limiter_test.rb` | allows under limit, blocks at limit, resets after window |
| `test/services/token_ledger_test.rb` | deducts atomically, raises on insufficient balance |
| `test/jobs/llm_inference_job_test.rb` | idempotency guard, broadcasts on success, sets failed on API error |
| `test/integration/messages_test.rb` | 429 on rate limit, 402 on no tokens, 200 happy path enqueues job |

---

## Concurrency edge cases addressed

| Scenario | Mitigation |
|---|---|
| Two simultaneous depletes of same user's token balance | `SELECT … FOR UPDATE` serialises the two transactions |
| Worker crashes after deducting tokens but before creating assistant message | `retry: 3` + idempotency check on `message.status`; tokens already deducted (acceptable — can refund in `discard_on` handler) |
| Rate limit window drift under clock skew | ZSET scores are Unix ms timestamps from the Redis server side (use `TIME` command if needed) |
| Duplicate job enqueue | `perform` starts with `return if message.completed?`; second run is a no-op |

---

## File checklist

```
app/
  models/
    user.rb
    conversation.rb
    message.rb
  services/
    rate_limiter.rb
    token_ledger.rb
  controllers/
    sessions_controller.rb
    conversations_controller.rb
    messages_controller.rb
  jobs/
    llm_inference_job.rb
  channels/
    conversations_channel.rb
  views/
    sessions/
      new.html.erb
    conversations/
      index.html.erb
      show.html.erb
    messages/
      _message.html.erb
      create.turbo_stream.erb
db/
  migrate/
    <ts>_create_users.rb
    <ts>_create_conversations.rb
    <ts>_create_messages.rb
    <ts>_add_indexes_to_messages.rb
config/
  cable.yml                  (update Redis adapter)
  initializers/
    sidekiq.rb
test/
  models/
    user_test.rb
    message_test.rb
  services/
    rate_limiter_test.rb
    token_ledger_test.rb
  jobs/
    llm_inference_job_test.rb
  integration/
    messages_test.rb
```
