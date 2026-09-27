# frozen_string_literal: true

require "test_helper"

class LlmInferenceJobTest < ActiveJob::TestCase
  FAKE_REPLY  = "Hi there!"
  FAKE_TOKENS = 12

  # Subclass that returns a canned response without hitting the API
  SuccessJob = Class.new(LlmInferenceJob) do
    def call_grok(_history)
      [ FAKE_REPLY, FAKE_TOKENS ]
    end
  end

  # Subclass that simulates an API error
  ErrorJob = Class.new(LlmInferenceJob) do
    def call_grok(_history)
      raise "Grok API timeout"
    end
  end

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

  test "creates assistant message and marks user message completed" do
    SuccessJob.perform_now(@message.id)

    assert @message.reload.status_completed?

    assistant = @conversation.messages.where(role: :assistant).last
    assert assistant, "expected an assistant message to be created"
    assert assistant.role_assistant?
    assert_equal FAKE_REPLY, assistant.content
    assert_equal FAKE_TOKENS, assistant.tokens_used
    assert assistant.status_completed?
  end

  test "idempotency — skips if message already completed" do
    @message.update!(status: :completed)

    assert_no_difference -> { @conversation.messages.count } do
      SuccessJob.perform_now(@message.id)
    end
  end

  test "idempotency — skips if message already failed" do
    @message.update!(status: :failed)

    assert_no_difference -> { @conversation.messages.count } do
      SuccessJob.perform_now(@message.id)
    end
  end

  test "sets message to failed on API error" do
    # retry_on catches the re-raise and enqueues a retry; the rescue block
    # still runs before that, so the status is set to :failed.
    ErrorJob.perform_now(@message.id)
    assert @message.reload.status_failed?
  end
end
