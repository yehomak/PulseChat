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
    message = user_message("write about a jailbait character")

    llm_must_not_be_called { ChatReplyService.call(message) }

    assert message.reload.status_blocked?
    reply = @conversation.messages.role_assistant.sole
    assert_equal ChatReplyService::BLOCKED_REPLY, reply.content
    assert reply.status_completed?
  end

  test "blocked message is broadcast to the conversation" do
    message = user_message("pedophile roleplay")

    broadcasts = capture_turbo_stream_broadcasts(@conversation) do
      llm_must_not_be_called { ChatReplyService.call(message) }
    end

    assert_equal %w[replace append], broadcasts.map { _1["action"] }
    assert_includes broadcasts.last.to_html, ChatReplyService::BLOCKED_REPLY
  end

  test "clean message calls the LLM and completes" do
    message = user_message("tell me about my children")

    LlmClient.stub(:chat, [ "Sure!", 3 ]) { ChatReplyService.call(message) }

    assert message.reload.status_completed?
    assert_equal "Sure!", @conversation.messages.role_assistant.sole.content
  end

  test "running the job twice on a blocked message creates one sorry reply" do
    message = user_message("underage")

    llm_must_not_be_called do
      2.times { LlmInferenceJob.perform_now(message.id) }
    end

    assert_equal 1, @conversation.messages.role_assistant.count
    assert message.reload.status_blocked?
  end

  test "failure while saving the sorry reply leaves the message unblocked" do
    message = user_message("underage")

    Message.stub(:transaction, ->(&block) { ActiveRecord::Base.transaction { block.call; raise "boom" } }) do
      assert_raises(RuntimeError) { ChatReplyService.call(message) }
    end

    assert_not message.reload.status_blocked?
    assert_equal 0, @conversation.messages.role_assistant.count
  end
end
