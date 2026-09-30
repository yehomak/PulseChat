# frozen_string_literal: true

class LlmInferenceJob < ApplicationJob
  queue_as :llm

  sidekiq_options queue: :llm, retry: 3

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(message_id)
    message = Message.find(message_id)
    ChatReplyService.call(message)
  rescue => e
    unless message&.status_cancelled?
      message&.update(status: :failed)
      broadcast_status(message) if message
    end
    raise
  end

  private

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
end
