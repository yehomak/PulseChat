# frozen_string_literal: true

class ConversationsChannel < ApplicationCable::Channel
  def subscribed
    conversation = current_user.conversations.find(params[:conversation_id])
    stream_for conversation
  rescue ActiveRecord::RecordNotFound
    reject
  end
end
