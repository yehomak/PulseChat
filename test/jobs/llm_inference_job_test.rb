# frozen_string_literal: true

require "test_helper"

class LlmInferenceJobTest < ActiveJob::TestCase
  FAKE_REPLY  = "Hi there!"
  FAKE_TOKENS = 12

  setup do
    @user = User.create!(
      email_address: "job@example.com",
      password: "password123",
      token_balance: 1000
    )
    @conversation = @user.conversations.create!(title: "Test")
    @message = @conversation.messages.create!(
      role: :user_message, content: "Hello Grok", status: :pending
    )
  end

  def with_llm_reply(reply = [ FAKE_REPLY, FAKE_TOKENS ], &)
    LlmClient.stub(:chat, reply, &)
  end

  def with_llm_error(&)
    LlmClient.stub(:chat, ->(_history) { raise "Grok API timeout" }, &)
  end

  test "creates assistant message and marks user message completed" do
    with_llm_reply { LlmInferenceJob.perform_now(@message.id) }

    assert @message.reload.status_completed?

    assistant = @conversation.messages.where(role: :assistant).last
    assert assistant, "expected an assistant message to be created"
    assert assistant.role_assistant?
    assert_equal FAKE_REPLY, assistant.content
    assert_equal FAKE_TOKENS, assistant.tokens_used
    assert assistant.status_completed?
  end

  test "passes conversation history to LlmClient" do
    received = nil
    LlmClient.stub(:chat, ->(history) { received = history; [ FAKE_REPLY, FAKE_TOKENS ] }) do
      LlmInferenceJob.perform_now(@message.id)
    end

    assert_equal [ { role: "user", content: "Hello Grok" } ], received
  end

  test "idempotency — skips if message already completed" do
    @message.update!(status: :completed)

    assert_no_difference -> { @conversation.messages.count } do
      with_llm_reply { LlmInferenceJob.perform_now(@message.id) }
    end
  end

  test "idempotency — skips if message already failed" do
    @message.update!(status: :failed)

    assert_no_difference -> { @conversation.messages.count } do
      with_llm_reply { LlmInferenceJob.perform_now(@message.id) }
    end
  end

  test "sets message to failed on API error" do
    # retry_on catches the re-raise and enqueues a retry; the rescue block
    # still runs before that, so the status is set to :failed.
    with_llm_error { LlmInferenceJob.perform_now(@message.id) }
    assert @message.reload.status_failed?
  end

  test "idempotency — skips if message already cancelled" do
    @message.update!(status: :cancelled)

    assert_no_difference -> { @conversation.messages.count } do
      with_llm_reply { LlmInferenceJob.perform_now(@message.id) }
    end
  end

  test "job detects Redis cancel signal and does not create assistant message" do
    cancel_mid_flight = lambda do |_history|
      $redis.setex("cancel:message:#{@message.id}", 600, "1")
      [ "partial reply", 5 ]
    end

    assert_no_difference -> { @conversation.messages.count } do
      LlmClient.stub(:chat, cancel_mid_flight) { LlmInferenceJob.perform_now(@message.id) }
    end

    assert_equal 0, $redis.exists("cancel:message:#{@message.id}"),
      "GETDEL should have consumed the cancel key"
  ensure
    $redis.del("cancel:message:#{@message.id}")
  end

  test "API error on cancelled message does not overwrite status with failed" do
    @message.update!(status: :cancelled)

    with_llm_error { LlmInferenceJob.perform_now(@message.id) }

    assert @message.reload.status_cancelled?,
      "rescue must not overwrite cancelled status with failed"
  end
end
