# frozen_string_literal: true

require "test_helper"

class ConversationsChannelTest < ActionCable::Channel::TestCase
  setup do
    @user = User.create!(
      email_address: "channel@example.com",
      password: "password123",
      token_balance: 1000
    )
    @conversation = @user.conversations.create!(title: "Cable test")
    stub_connection current_user: @user
  end

  test "subscribes and streams for conversation" do
    subscribe conversation_id: @conversation.id
    assert subscription.confirmed?
  end

  test "rejects subscription for conversation not owned by user" do
    other_user = User.create!(
      email_address: "other@example.com",
      password: "password123",
      token_balance: 1000
    )
    other_conversation = other_user.conversations.create!(title: "Not yours")

    subscribe conversation_id: other_conversation.id
    assert subscription.rejected?
  end
end
