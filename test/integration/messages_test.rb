# frozen_string_literal: true

require "test_helper"

class MessagesTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email_address: "user@example.com",
      password: "password123",
      token_balance: 1000
    )
    @conversation = @user.conversations.create!(title: "Test chat")
    sign_in_as @user
  end

  test "happy path enqueues LlmInferenceJob and returns turbo stream" do
    assert_difference -> { @conversation.messages.count }, 1 do
      assert_enqueued_with(job: LlmInferenceJob) do
        post conversation_messages_path(@conversation),
             params: { message: { content: "Hello!" } },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    assert_response :success
    assert_equal :pending, @conversation.messages.last.status.to_sym
  end

  test "returns 429 when rate limit exceeded" do
    RateLimiter::LIMIT.times do
      post conversation_messages_path(@conversation),
           params: { message: { content: "ping" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_no_enqueued_jobs(only: LlmInferenceJob) do
      post conversation_messages_path(@conversation),
           params: { message: { content: "one too many" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :too_many_requests
  end

  test "returns 402 when token balance is insufficient" do
    @user.update_columns(token_balance: 0)

    assert_no_enqueued_jobs(only: LlmInferenceJob) do
      post conversation_messages_path(@conversation),
           params: { message: { content: "no tokens" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :payment_required
  end

  test "redirects unauthenticated request to login" do
    sign_out
    post conversation_messages_path(@conversation),
         params: { message: { content: "sneaky" } }
    assert_redirected_to new_session_path
  end
end
