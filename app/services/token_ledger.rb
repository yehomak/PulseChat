# frozen_string_literal: true

class TokenLedger
  class InsufficientTokens < StandardError; end

  def initialize(user_id:)
    @user_id = user_id
  end

  def deduct!(amount)
    User.transaction do
      user = User.lock("FOR UPDATE").find(@user_id)

      raise InsufficientTokens if user.token_balance < amount

      user.update_columns(token_balance: user.token_balance - amount)
      user.token_balance
    end
  end
end
