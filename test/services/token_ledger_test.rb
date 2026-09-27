# frozen_string_literal: true

require "test_helper"

class TokenLedgerTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email_address: "ledger@example.com",
      password: "password123",
      token_balance: 500
    )
    @ledger = TokenLedger.new(user_id: @user.id)
  end

  test "deducts amount and returns remaining balance" do
    remaining = @ledger.deduct!(100)
    assert_equal 400, remaining
    assert_equal 400, @user.reload.token_balance
  end

  test "raises InsufficientTokens when balance is too low" do
    assert_raises(TokenLedger::InsufficientTokens) do
      @ledger.deduct!(600)
    end
  end

  test "does not deduct on InsufficientTokens" do
    @ledger.deduct!(600) rescue nil
    assert_equal 500, @user.reload.token_balance
  end

  test "deducting exact balance leaves zero" do
    remaining = @ledger.deduct!(500)
    assert_equal 0, remaining
  end
end
