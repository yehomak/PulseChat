# frozen_string_literal: true

class MessagesController < ApplicationController
  before_action :set_conversation

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

    LlmInferenceJob.perform_later(@message.id)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @conversation }
    end
  end

  private

  def set_conversation
    @conversation = Current.user.conversations.find(params[:conversation_id])
  end

  def message_params
    params.expect(message: [ :content ])
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
