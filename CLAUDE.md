# EverChat-Mini Practice Project Constraints

## Tech Stack
- Ruby 3.4.9, Rails 8.1.3 (Monolith)
- PostgreSQL (with `pgvector`), Redis, Sidekiq
- Hotwire (Turbo Streams + Stimulus), ActionCable, Propshaft, Tailwind

## Code Conventions & Standards
1. **Rails 8 Idioms**: Use `params.expect` for strong parameters instead of `params.require`.
2. **Controller/Service Layer**: Keep controllers thin. Delegate complex domain logic to service objects under `app/services/`.
3. **Background Jobs (Sidekiq)**:
   - Always pass primitive arguments (e.g., `message.id`) to `#perform_async` / `#perform_later`. Never pass ActiveRecord model instances.
   - Set explicit retry options: `sidekiq_options queue: :default, retry: 3`.
   - Ensure jobs are idempotent with early state checks (e.g., `return if message.completed?`).
4. **Concurrency & Locking**:
   - Use `User.lock("FOR UPDATE")` or atomic SQL updates for sensitive mutations (like token counts).
   - Use Redis ZSET for sliding-window rate limiters wrapped in `$redis.multi`.
5. **Real-time UI**:
   - Broadcast live DOM updates using `Turbo::StreamsChannel.broadcast_replace_to` or `broadcast_append_to`.
   - Use `<%= turbo_stream_from ... %>` in view templates.
6. **Database & Indexing**:
   - Explicitly define composite indexes for sorted queries (e.g., `[:conversation_id, :created_at]`).
   - Use partial indexes where applicable (e.g., `where: "active = TRUE"`).

## Testing
- Prefer concise Rails Minitest integration/unit tests for core models and jobs.

## Claude Code tooling

Read `.claude/conventions.md` before creating or placing any file.

**Commands:** `/commit` `/pr` `/migrate` `/grilling` `/diagnosing-bugs` `/wait-what` `/handoff`

**Agents:** `rails-reviewer` · `job-agent` · `turbo-agent` · `query-agent`

**Hooks (automatic):** rubocop-gate on Stop · frozen-string-literal on Write · callback-lint on Write · n1-detector after test runs · migration-guard on destructive DB commands