# frozen_string_literal: true

class LlmInferenceJob < ApplicationJob
  queue_as :llm

  sidekiq_options queue: :llm, retry: 3

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(message_id)
    message = Message.find(message_id)
    return if message.status_completed? || message.status_failed?

    message.update!(status: :streaming)

    history  = build_history(message)
    content, tokens_used = call_grok(history)

    assistant_message = message.conversation.messages.create!(
      role:        :assistant,
      content:     content,
      status:      :completed,
      tokens_used: tokens_used
    )

    message.update!(status: :completed)

    begin
      broadcast(message, assistant_message)
    rescue => e
      # Broadcast failure is non-fatal — message is already persisted as completed.
      # Log and move on rather than rolling back visible state or triggering a retry.
      Rails.logger.error("LlmInferenceJob broadcast error: #{e.class} #{e.message}")
    end
  rescue => e
    message&.update(status: :failed)
    raise
  end

  private

  def build_history(message)
    message.conversation.messages
           .where("id <= ?", message.id)
           .ordered
           .map { { role: grok_role(_1.role), content: _1.content } }
  end

  def grok_role(role)
    role == "assistant" ? "assistant" : "user"
  end

  def call_grok(history)
    client = OpenAI::Client.new(
      access_token: ENV.fetch("XAI_API_KEY"),
      uri_base:     "https://api.x.ai/v1"
    )

    response = client.chat(
      parameters: {
        model:      "grok-3-mini",
        messages:   history,
        max_tokens: 1000
      }
    )

    content     = response.dig("choices", 0, "message", "content").to_s
    tokens_used = response.dig("usage", "completion_tokens").to_i

    [ content, tokens_used ]
  end

  def broadcast(user_message, assistant_message)
    conversation = user_message.conversation

    Turbo::StreamsChannel.broadcast_replace_to(
      conversation,
      target:  ActionView::RecordIdentifier.dom_id(user_message),
      partial: "messages/message",
      locals:  { message: user_message }
    )

    Turbo::StreamsChannel.broadcast_append_to(
      conversation,
      target:  "messages",
      partial: "messages/message",
      locals:  { message: assistant_message }
    )
  end
end
