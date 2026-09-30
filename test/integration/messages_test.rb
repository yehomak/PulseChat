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

  # Cancel action tests

  test "cancel sets message to cancelled and writes Redis key" do
    message = @conversation.messages.create!(role: :user_message, content: "hi", status: :streaming)

    patch cancel_conversation_message_path(@conversation, message)

    assert_response :no_content
    assert message.reload.status_cancelled?
    assert $redis.exists("cancel:message:#{message.id}") == 1
  ensure
    $redis.del("cancel:message:#{message.id}")
  end

  test "cancel on pending message also succeeds" do
    message = @conversation.messages.create!(role: :user_message, content: "hi", status: :pending)

    patch cancel_conversation_message_path(@conversation, message)

    assert_response :no_content
    assert message.reload.status_cancelled?
  ensure
    $redis.del("cancel:message:#{message.id}")
  end

  test "cancel on blocked message returns 422 and does not write Redis key" do
    message = @conversation.messages.create!(role: :user_message, content: "hi", status: :blocked)

    patch cancel_conversation_message_path(@conversation, message)

    assert_response :unprocessable_entity
    assert message.reload.status_blocked?
    assert $redis.exists("cancel:message:#{message.id}") == 0
  end

  test "blocked message shows the moderation label and no stop button" do
    @conversation.messages.create!(role: :user_message, content: "hi", status: :blocked)

    get conversation_path(@conversation)

    assert_response :success
    assert_select "p", text: "Blocked by moderation"
    assert_select "form[action$='/cancel']", count: 0
  end

  test "cancel on completed message returns 422 and does not write Redis key" do
    message = @conversation.messages.create!(role: :user_message, content: "hi", status: :completed)

    patch cancel_conversation_message_path(@conversation, message)

    assert_response :unprocessable_entity
    assert message.reload.status_completed?
    assert $redis.exists("cancel:message:#{message.id}") == 0
  end

  test "cannot cancel another user's message" do
    other_user = User.create!(email_address: "other@example.com", password: "password123", token_balance: 0)
    other_conversation = other_user.conversations.create!(title: "Other chat")
    other_message = other_conversation.messages.create!(role: :user_message, content: "hi", status: :streaming)

    patch cancel_conversation_message_path(other_conversation, other_message)

    assert_response :not_found
    assert other_message.reload.status_streaming?
  end

  test "cancel Redis key expires after TTL and a second cancel on same message returns 422" do
    message = @conversation.messages.create!(role: :user_message, content: "hi", status: :streaming)
    patch cancel_conversation_message_path(@conversation, message)
    assert_response :no_content

    patch cancel_conversation_message_path(@conversation, message)
    assert_response :unprocessable_entity
  ensure
    $redis.del("cancel:message:#{message.id}")
  end
end
