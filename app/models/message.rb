# frozen_string_literal: true

class Message < ApplicationRecord
  # Associations
  belongs_to :conversation

  # Enums
  enum :role,   { user_message: 0, assistant: 1 }, prefix: true
  enum :status, { pending: 0, streaming: 1, completed: 2, failed: 3, cancelled: 4 }, prefix: true

  # Validations
  validates :content, presence: true

  # Scopes
  scope :ordered, -> { order(:created_at) }
end
