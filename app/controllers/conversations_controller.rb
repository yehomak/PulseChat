# frozen_string_literal: true

class ConversationsController < ApplicationController
  before_action :set_conversation, only: [:show, :edit, :update, :destroy]

  def index
    @conversations = Current.user.conversations.recent
  end

  def show
    @messages = @conversation.messages.ordered
    @message  = @conversation.messages.build
  end

  def new
    @conversation = Current.user.conversations.build
  end

  def create
    @conversation = Current.user.conversations.build(conversation_params)
    if @conversation.save
      redirect_to @conversation
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @conversation.destroy
    redirect_to conversations_path, status: :see_other
  end

  private

  def set_conversation
    @conversation = Current.user.conversations.find(params[:id])
  end

  def conversation_params
    params.expect(conversation: [:title])
  end
end
