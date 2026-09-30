# frozen_string_literal: true

class RateLimiter
  WINDOW_SECONDS = 60
  LIMIT          = 10

  # Evict, count, and record only if under the limit, atomically. Recording before checking
  # would let rejected attempts fill the window, keeping a retrying client blocked indefinitely.
  SCRIPT = <<~LUA
    local key, now, window, limit, member = KEYS[1], tonumber(ARGV[1]), tonumber(ARGV[2]), tonumber(ARGV[3]), ARGV[4]
    redis.call("ZREMRANGEBYSCORE", key, 0, now - window)
    if redis.call("ZCARD", key) >= limit then
      return 0
    end
    redis.call("ZADD", key, now, member)
    redis.call("PEXPIRE", key, window)
    return 1
  LUA

  def initialize(user_id:)
    @key = "rate:#{user_id}"
  end

  def allowed?
    now_ms = (Time.now.to_f * 1000).to_i
    member = "#{now_ms}:#{SecureRandom.hex(8)}"

    $redis.eval(SCRIPT, keys: [ @key ], argv: [ now_ms, WINDOW_SECONDS * 1000, LIMIT, member ]) == 1
  end
end
