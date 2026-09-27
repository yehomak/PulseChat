# frozen_string_literal: true

class Conversation < ApplicationRecord
  # Associations
  belongs_to :user
  has_many :messages, dependent: :destroy

  # Validations
  validates :title, presence: true

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
end
