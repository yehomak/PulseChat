# frozen_string_literal: true

require "test_helper"

class RateLimiterTest < ActiveSupport::TestCase
  setup do
    @user_id = 99999
    $redis.del("rate:#{@user_id}")
  end

  teardown do
    $redis.del("rate:#{@user_id}")
  end

  test "allows requests under the limit" do
    limiter = RateLimiter.new(user_id: @user_id)
    RateLimiter::LIMIT.times do
      assert limiter.allowed?
    end
  end

  test "blocks the request that exceeds the limit" do
    limiter = RateLimiter.new(user_id: @user_id)
    RateLimiter::LIMIT.times { limiter.allowed? }
    assert_not limiter.allowed?
  end

  test "allows again after window expires" do
    limiter = RateLimiter.new(user_id: @user_id)
    RateLimiter::LIMIT.times { limiter.allowed? }

    # Manually backdate all scores so they fall outside the window
    old_score = (Time.now.to_f * 1000).to_i - (RateLimiter::WINDOW_SECONDS * 1000 + 1)
    members = $redis.zrange("rate:#{@user_id}", 0, -1)
    members.each { $redis.zadd("rate:#{@user_id}", old_score, _1) }

    assert limiter.allowed?
  end
end
