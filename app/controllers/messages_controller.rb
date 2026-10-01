# frozen_string_literal: true

class MessagesController < ApplicationController
  before_action :set_conversation
  before_action :set_message, only: [ :cancel ]

  def create
    unless RateLimiter.new(user_id: Current.user.id).allowed?
      return respond_with_error(:too_many_requests, "Slow down — you're sending messages too fast.")
    end

    cost = estimate_cost(message_params[:content])

    begin
      TokenLedger.new(user_id: Current.user.id).deduct!(cost)
    rescue TokenLedger::InsufficientTokens
      return respond_with_error(:payment_required, "Not enough tokens. Please top up your balance.")
    end

    @message = @conversation.messages.create!(
      role:    :user_message,
      content: message_params[:content],
      status:  :pending
    )

    broadcast_user_message
    LlmInferenceJob.perform_later(@message.id)

    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_to @conversation }
    end
  end

  def cancel
    return head :unprocessable_entity if @message.finished?

    @message.status_cancelled!
    $redis.setex("cancel:message:#{@message.id}", 600, "1")

    begin
      Turbo::StreamsChannel.broadcast_replace_to(
        @conversation,
        target:  ActionView::RecordIdentifier.dom_id(@message),
        partial: "messages/message",
        locals:  { message: @message, conversation: @conversation }
      )
    rescue => e
      Rails.logger.error("cancel broadcast error: #{e.class} #{e.message}")
    end

    head :no_content
  end

  private

  def set_conversation
    @conversation = Current.user.conversations.find(params[:conversation_id])
  end

  def set_message
    @message = @conversation.messages.find(params[:id])
  end

  def message_params
    params.expect(message: [ :content ])
  end

  # Sent over the same stream as the job's broadcasts, and before the job is enqueued, so the
  # bubble always arrives first. Rendering it in the HTTP response raced fast jobs: a blocked
  # reply could arrive before the message it answers.
  def broadcast_user_message
    Turbo::StreamsChannel.broadcast_append_to(
      @conversation,
      target:  "messages",
      partial: "messages/message",
      locals:  { message: @message, conversation: @conversation }
    )
  rescue => e
    Rails.logger.error("user message broadcast error: #{e.class} #{e.message}")
  end

  def estimate_cost(content)
    (content.to_s.length / 4.0).ceil.clamp(1, 2000)
  end

  def respond_with_error(status, alert)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("flash", alert), status: status }
      format.html         { redirect_to @conversation, alert: alert, status: status }
    end
  end
end
