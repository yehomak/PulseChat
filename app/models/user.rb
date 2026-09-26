# frozen_string_literal: true

class User < ApplicationRecord
  # Associations
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :conversations, dependent: :destroy

  # Normalizations
  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # Validations
  validates :email_address, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token_balance, numericality: { greater_than_or_equal_to: 0 }
end
