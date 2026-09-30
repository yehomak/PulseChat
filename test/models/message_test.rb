# frozen_string_literal: true

require "test_helper"

class MessageTest < ActiveSupport::TestCase
  # Stored as integers: renumbering an existing status would silently rewrite historical rows.
  test "status integer mapping is stable" do
    assert_equal(
      { "pending" => 0, "streaming" => 1, "completed" => 2, "failed" => 3, "cancelled" => 4, "blocked" => 5 },
      Message.statuses
    )
  end

  test "finished? covers every terminal status and nothing else" do
    finished = Message.statuses.keys.select { Message.new(status: _1).finished? }
    assert_equal %w[completed failed cancelled blocked], finished
  end

  test "blocked messages are queryable for audit" do
    user = User.create!(email_address: "audit@example.com", password: "password123")
    conversation = user.conversations.create!(title: "Audit")
    blocked = conversation.messages.create!(role: :user_message, content: "x", status: :blocked)
    conversation.messages.create!(role: :user_message, content: "y", status: :completed)

    assert_equal [ blocked ], Message.status_blocked.to_a
  end
end
