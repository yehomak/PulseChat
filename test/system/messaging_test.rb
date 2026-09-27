# frozen_string_literal: true

require "application_system_test_case"

class MessagingTest < ApplicationSystemTestCase
  setup do
    @user = User.create!(
      email_address: "system@example.com",
      password: "password123",
      token_balance: 10_000
    )
  end

  test "sign in and land on conversations page" do
    visit new_session_path

    fill_in "Enter your email address", with: @user.email_address
    fill_in "Enter your password", with: "password123"
    click_on "Sign in"

    assert_current_path root_path
    assert_text "Conversations"
  end

  test "create a new conversation" do
    sign_in_as @user

    visit new_conversation_path
    fill_in "Title", with: "Test convo"
    click_on "Create"

    assert_text "Test convo"
  end

  test "send a message and see it appear" do
    sign_in_as @user
    conversation = @user.conversations.create!(title: "Chat")

    visit conversation_path(conversation)

    fill_in placeholder: "Message…", with: "Hello there"
    click_on "Send"

    assert_selector "#messages", text: "Hello there"
  end

  test "Stop button cancels a streaming message and shows stopped badge" do
    sign_in_as @user
    conversation = @user.conversations.create!(title: "Cancel test")
    message = conversation.messages.create!(
      role: :user_message, content: "Generate something long", status: :streaming
    )

    visit conversation_path(conversation)

    assert_selector "##{dom_id(message)}", text: "…"
    assert_button "Stop"

    click_on "Stop"

    assert_no_button "Stop"
    assert_selector "##{dom_id(message)}", text: "Generation stopped"
  end

  private

  def sign_in_as(user)
    visit new_session_path
    fill_in "Enter your email address", with: user.email_address
    fill_in "Enter your password", with: "password123"
    click_on "Sign in"
    assert_current_path root_path
  end
end
