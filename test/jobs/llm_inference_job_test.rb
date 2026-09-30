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
    LlmClient.stub(:chat, ->(_history) { raise "unexpected provider response" }, &)
  end

  # Raises error_class for the first `failures` calls, then replies. Returns the call count.
  def with_flaky_llm(error_class, failures:)
    calls = 0
    flaky = lambda do |_history|
      calls += 1
      raise error_class, "attempt #{calls}" if calls <= failures
      [ FAKE_REPLY, FAKE_TOKENS ]
    end
    LlmClient.stub(:chat, flaky) { yield }
    calls
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

  test "sends only the most recent HISTORY_LIMIT messages, oldest first" do
    base = 1.hour.ago
    older = Array.new(ChatReplyService::HISTORY_LIMIT + 5) do |i|
      { conversation_id: @conversation.id, role: 0, status: 2, content: "old #{i}",
        created_at: base + i.seconds, updated_at: base + i.seconds }
    end
    Message.insert_all!(older)
    latest = @conversation.messages.create!(role: :user_message, content: "latest", status: :pending)

    received = nil
    LlmClient.stub(:chat, ->(history) { received = history; [ FAKE_REPLY, FAKE_TOKENS ] }) do
      LlmInferenceJob.perform_now(latest.id)
    end

    assert_equal ChatReplyService::HISTORY_LIMIT, received.size
    # 55 old + setup's "Hello Grok" + latest = 57; the 7 oldest are dropped.
    assert_equal [ "Hello Grok", "latest" ], received.last(2).pluck(:content)
    assert_equal "old 7", received.first[:content]
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

  test "non-retryable error fails the message immediately without retrying" do
    assert_no_enqueued_jobs do
      with_llm_error { LlmInferenceJob.perform_now(@message.id) }
    end
    assert @message.reload.status_failed?
  end

  test "transient error is retried and the reply completes" do
    calls = with_flaky_llm(Faraday::TimeoutError, failures: 1) do
      perform_enqueued_jobs { LlmInferenceJob.perform_later(@message.id) }
    end

    assert_equal 2, calls
    assert @message.reload.status_completed?
    assert_equal FAKE_REPLY, @conversation.messages.role_assistant.sole.content
  end

  test "message stays streaming while a retry is pending" do
    with_flaky_llm(Faraday::TooManyRequestsError, failures: 1) do
      LlmInferenceJob.perform_now(@message.id)
    end

    assert @message.reload.status_streaming?
    assert_enqueued_jobs 1, only: LlmInferenceJob
  end

  test "transient errors fail the message once attempts are exhausted" do
    calls = with_flaky_llm(Faraday::ServerError, failures: 99) do
      perform_enqueued_jobs { LlmInferenceJob.perform_later(@message.id) }
    end

    assert_equal 3, calls
    assert @message.reload.status_failed?
    assert_equal 0, @conversation.messages.role_assistant.count
  end

  test "auth error is not retried" do
    calls = with_flaky_llm(Faraday::UnauthorizedError, failures: 99) do
      perform_enqueued_jobs { LlmInferenceJob.perform_later(@message.id) }
    end

    assert_equal 1, calls
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

  test "cancel persisted during the LLM call does not create assistant message" do
    cancel_in_db = lambda do |_history|
      Message.find(@message.id).update!(status: :cancelled)
      [ "partial reply", 5 ]
    end

    assert_no_difference -> { @conversation.messages.count } do
      LlmClient.stub(:chat, cancel_in_db) { LlmInferenceJob.perform_now(@message.id) }
    end

    assert @message.reload.status_cancelled?
  end

  test "API error on cancelled message does not overwrite status with failed" do
    @message.update!(status: :cancelled)

    with_llm_error { LlmInferenceJob.perform_now(@message.id) }

    assert @message.reload.status_cancelled?,
      "rescue must not overwrite cancelled status with failed"
  end
end
