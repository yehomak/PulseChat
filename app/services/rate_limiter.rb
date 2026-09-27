# frozen_string_literal: true

class RateLimiter
  WINDOW_SECONDS = 60
  LIMIT          = 10

  def initialize(user_id:)
    @key = "rate:#{user_id}"
  end

  def allowed?
    now_ms = (Time.now.to_f * 1000).to_i

    member = "#{now_ms}:#{SecureRandom.hex(8)}"

    results = $redis.multi do |r|
      r.zadd(@key, now_ms, member)
      r.zremrangebyscore(@key, 0, now_ms - (WINDOW_SECONDS * 1000))
      r.expire(@key, WINDOW_SECONDS)
      r.zcard(@key)
    end

    results[3] <= LIMIT
  end
end
