# Conventions — EverAI Interview Project

Read this file before creating, placing, or naming any file.

---

## Branch naming

| Pattern | When |
|---|---|
| `agent/<topic>-<short-desc>` | AI-assisted work (`agent/task1-reactions`, `agent/task2-archive`) |
| `feat/<desc>` | New feature (manual) |
| `fix/<desc>` | Bug fix |
| `db/<desc>` | Migration only |
| `refactor/<desc>` | No behaviour change |

Never commit directly to `main`.

---

## Commit format

```
<type>(<optional scope>): <subject>
```

**Types:** `feat` `fix` `db` `refactor` `test` `docs` `chore` `perf`

**Scope** = Rails layer: `(model)` `(controller)` `(job)` `(channel)` `(view)`

**Rules:**
- Subject ≤ 72 chars, imperative mood ("add X" not "added X")
- No AI mention in commit messages

**Examples:**
```
feat(model): add Reaction model with polymorphic target
feat(job): broadcast reaction count after save
db: add reactions table with index on target
fix(channel): scope MessagesChannel to current user
test(model): add Reaction validation specs
```

---

## File placement

| File type | Path |
|---|---|
| Model | `app/models/<name>.rb` |
| Controller | `app/controllers/<name>_controller.rb` |
| Job | `app/jobs/<name>_job.rb` |
| Channel | `app/channels/<name>_channel.rb` |
| Mailer | `app/mailers/<name>_mailer.rb` |
| Model concern | `app/models/concerns/<name>.rb` |
| Controller concern | `app/controllers/concerns/<name>.rb` |
| View | `app/views/<controller>/<action>.html.erb` |
| Partial | `app/views/<controller>/_<name>.html.erb` |
| Migration | `db/migrate/<timestamp>_<description>.rb` |
| Test (model) | `test/models/<name>_test.rb` |
| Test (job) | `test/jobs/<name>_job_test.rb` |
| Test (channel) | `test/channels/<name>_channel_test.rb` |
| Test (request) | `test/integration/<name>_test.rb` |
| Fixtures | `test/fixtures/<table_name>.yml` |

---

## Model — section order

```ruby
# frozen_string_literal: true

class Message < ApplicationRecord
  # 1. Associations
  belongs_to :user
  has_many :reactions, as: :target, dependent: :destroy

  # 2. Enums
  enum :status, { pending: 0, delivered: 1, failed: 2 }, prefix: true

  # 3. Normalizations
  normalizes :content, with: -> { _1.strip }

  # 4. Validations
  validates :content, presence: true, length: { maximum: 10_000 }

  # 5. Scopes
  scope :recent, -> { order(created_at: :desc) }

  # 6. Callbacks — lambda syntax, *_commit for any async work
  after_create_commit -> { broadcast_later }

  # 7. Public methods
  def broadcast_later = MessageBroadcastJob.perform_later(id)
  def broadcast_now   = broadcast_append_to(user, "messages")

  private

  # 8. Private methods
end
```

---

## Controller — section order

```ruby
# frozen_string_literal: true

class MessagesController < ApplicationController
  # 1. Before actions
  before_action :authenticate_user!
  before_action :set_conversation
  before_action :set_message, only: [:show, :update, :destroy]

  # 2. REST actions only — no custom action names
  def index
    @messages = @conversation.messages.includes(:user).recent
  end

  def create
    @message = @conversation.messages.build(message_params)
    @message.user = Current.user
    if @message.save
      respond_to { |f| f.turbo_stream; f.html { redirect_to @conversation } }
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  # 3. Finders — always scoped to Current.user
  def set_conversation = @conversation = Current.user.conversations.find(params[:conversation_id])
  def set_message      = @message = @conversation.messages.find(params[:id])
  def message_params   = params.expect(message: [:content])
end
```

---

## Job — section order

```ruby
# frozen_string_literal: true

class MessageBroadcastJob < ApplicationJob
  # 1. Queue — explicit, never :default for ML/media
  queue_as :default

  # 2. Error policy
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  # 3. Perform — shallow wrapper only, no business logic
  def perform(message_id)
    Message.find(message_id).broadcast_now
  end
end
```

---

## Migration — section order

```ruby
# frozen_string_literal: true

class AddReactionsTable < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!  # only when using algorithm: :concurrently

  def change
    create_table :reactions do |t|
      t.references :user,   null: false, foreign_key: true
      t.references :target, null: false, polymorphic: true
      t.string :kind,       null: false
      t.timestamps
    end

    add_index :reactions, [:target_type, :target_id], algorithm: :concurrently
  end
  # Always reversible — ActiveRecord handles drop_table on rollback
end
```

---

## Test — section order

```ruby
# frozen_string_literal: true

require "test_helper"

class MessageTest < ActiveSupport::TestCase
  # 1. Validations
  test "valid with required attributes" do; end
  test "invalid without content" do; end

  # 2. Scopes
  test "recent returns newest first" do; end

  # 3. Instance methods — test _now directly (no job involved)
  test "broadcast_now sends turbo stream" do; end

  # 4. Callbacks — trigger via model action, assert on job enqueue
  test "enqueues broadcast job after create" do
    assert_enqueued_with(job: MessageBroadcastJob) do
      Message.create!(valid_attributes)
    end
  end
end
```
