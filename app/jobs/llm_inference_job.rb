# frozen_string_literal: true

class LlmInferenceJob < ApplicationJob
  queue_as :llm

  sidekiq_options queue: :llm, retry: 3

  # Most recent messages sent as context: bounds per-job DB work and the LLM context window.
  HISTORY_LIMIT = 50

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(message_id)
    message = Message.find(message_id)
    return if message.status_completed? || message.status_failed? || message.status_cancelled?

    message.update!(status: :streaming)

    history  = build_history(message)
    content, tokens_used = LlmClient.chat(history)

    return if $redis.getdel("cancel:message:#{message_id}").present? || message.reload.status_cancelled?

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
    unless message&.status_cancelled?
      message&.update(status: :failed)
      broadcast_status(message) if message
    end
    raise
  end

  private

  def build_history(message)
    message.conversation.messages
           .where("id <= ?", message.id)
           .ordered.reverse_order
           .limit(HISTORY_LIMIT)
           .reverse
           .map { { role: grok_role(_1.role), content: _1.content } }
  end

  def grok_role(role)
    role == "assistant" ? "assistant" : "user"
  end

  def broadcast_status(message)
    Turbo::StreamsChannel.broadcast_replace_to(
      message.conversation,
      target:  ActionView::RecordIdentifier.dom_id(message),
      partial: "messages/message",
      locals:  { message: message, conversation: message.conversation }
    )
  rescue => e
    Rails.logger.error("LlmInferenceJob status broadcast error: #{e.class} #{e.message}")
  end

  def broadcast(user_message, assistant_message)
    conversation = user_message.conversation

    Turbo::StreamsChannel.broadcast_replace_to(
      conversation,
      target:  ActionView::RecordIdentifier.dom_id(user_message),
      partial: "messages/message",
      locals:  { message: user_message, conversation: conversation }
    )

    Turbo::StreamsChannel.broadcast_append_to(
      conversation,
      target:  "messages",
      partial: "messages/message",
      locals:  { message: assistant_message, conversation: conversation }
    )
  end
end
