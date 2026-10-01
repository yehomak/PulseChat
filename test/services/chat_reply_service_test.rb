# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

class ChatReplyServiceTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    user = User.create!(email_address: "reply@example.com", password: "password123")
    @conversation = user.conversations.create!(title: "Test")
  end

  def user_message(content)
    @conversation.messages.create!(role: :user_message, content:, status: :pending)
  end

  def llm_must_not_be_called(&)
    LlmClient.stub(:chat, ->(_history) { flunk "LlmClient was called for a blocked message" }, &)
  end

  test "blocked message is marked blocked and gets the sorry reply" do
    message = user_message("you are a dumbass")

    llm_must_not_be_called { ChatReplyService.call(message) }

    assert message.reload.status_blocked?
    reply = @conversation.messages.role_assistant.sole
    assert_equal ChatReplyService::BLOCKED_REPLY, reply.content
    assert reply.status_completed?
  end

  test "blocked message is broadcast to the conversation" do
    message = user_message("shut up, moron")

    broadcasts = capture_turbo_stream_broadcasts(@conversation) do
      llm_must_not_be_called { ChatReplyService.call(message) }
    end

    assert_equal %w[replace append], broadcasts.map { _1["action"] }
    assert_includes broadcasts.last.to_html, ChatReplyService::BLOCKED_REPLY
  end

  test "blocked turn is excluded from the next message's history" do
    blocked = user_message("you dumbass")
    llm_must_not_be_called { ChatReplyService.call(blocked) }
    user_typed_apology = user_message(ChatReplyService::BLOCKED_REPLY)
    user_typed_apology.update!(status: :completed)
    follow_up = user_message("why")

    sent = nil
    LlmClient.stub(:chat, ->(history) { sent = history; [ "ok", 1 ] }) { ChatReplyService.call(follow_up) }

    assert_equal [ ChatReplyService::BLOCKED_REPLY, "why" ], sent.pluck(:content),
      "only the user's own messages should remain; the blocked text and canned reply must be gone"
    assert_equal %w[user user], sent.pluck(:role)
  end

  test "clean message calls the LLM and completes" do
    message = user_message("tell me about my children")

    LlmClient.stub(:chat, [ "Sure!", 3 ]) { ChatReplyService.call(message) }

    assert message.reload.status_completed?
    assert_equal "Sure!", @conversation.messages.role_assistant.sole.content
  end

  test "running the job twice on a blocked message creates one sorry reply" do
    message = user_message("idiot")

    llm_must_not_be_called do
      2.times { LlmInferenceJob.perform_now(message.id) }
    end

    assert_equal 1, @conversation.messages.role_assistant.count
    assert message.reload.status_blocked?
  end

  test "failure while saving the sorry reply leaves the message unblocked" do
    message = user_message("idiot")

    Message.stub(:transaction, ->(&block) { ActiveRecord::Base.transaction { block.call; raise "boom" } }) do
      assert_raises(RuntimeError) { ChatReplyService.call(message) }
    end

    assert_not message.reload.status_blocked?
    assert_equal 0, @conversation.messages.role_assistant.count
  end
end
