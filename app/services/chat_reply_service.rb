# frozen_string_literal: true

# Produces the assistant reply to a user message: history, LLM call, persistence, broadcast.
class ChatReplyService
  # Most recent messages sent as context: bounds per-job DB work and the LLM context window.
  HISTORY_LIMIT = 50

  def self.call(message)
    new(message).call
  end

  def initialize(message)
    @message = message
  end

  def call
    return if @message.status_completed? || @message.status_failed? || @message.status_cancelled?

    @message.update!(status: :streaming)

    content, tokens_used = LlmClient.chat(build_history)

    return if cancelled?

    reply = conversation.messages.create!(
      role:        :assistant,
      content:     content,
      status:      :completed,
      tokens_used: tokens_used
    )

    @message.update!(status: :completed)

    broadcast(reply)
  end

  private

  # Not memoised: cancelled? reloads the message, and the old job re-read the association after that.
  def conversation
    @message.conversation
  end

  def cancelled?
    $redis.getdel("cancel:message:#{@message.id}").present? || @message.reload.status_cancelled?
  end

  def build_history
    conversation.messages
                .where("id <= ?", @message.id)
                .ordered.reverse_order
                .limit(HISTORY_LIMIT)
                .reverse
                .map { { role: llm_role(_1.role), content: _1.content } }
  end

  def llm_role(role)
    role == "assistant" ? "assistant" : "user"
  end

  # Non-fatal: the reply is already persisted, so a failed broadcast must not trigger a retry.
  def broadcast(reply)
    Turbo::StreamsChannel.broadcast_replace_to(
      conversation,
      target:  ActionView::RecordIdentifier.dom_id(@message),
      partial: "messages/message",
      locals:  { message: @message, conversation: conversation }
    )

    Turbo::StreamsChannel.broadcast_append_to(
      conversation,
      target:  "messages",
      partial: "messages/message",
      locals:  { message: reply, conversation: conversation }
    )
  rescue => e
    Rails.logger.error("ChatReplyService broadcast error: #{e.class} #{e.message}")
  end
end
