# frozen_string_literal: true

class Message < ApplicationRecord
  # Associations
  belongs_to :conversation

  # Enums
  enum :role,   { user_message: 0, assistant: 1 }, prefix: true
  enum :status, { pending: 0, streaming: 1, completed: 2, failed: 3, cancelled: 4, blocked: 5 }, prefix: true

  FINISHED_STATUSES = %w[completed failed cancelled blocked].freeze

  # Validations
  validates :content, presence: true

  # Scopes
  scope :ordered, -> { order(:created_at) }

  # No further work (reply, cancel) applies to a message in one of these states.
  def finished?
    status.in?(FINISHED_STATUSES)
  end
end
