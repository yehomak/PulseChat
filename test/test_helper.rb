ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Tests never touch development Redis (DB 0 app/Sidekiq, DB 1 cable). Connections are
    # reassigned here rather than via ENV because a full `bin/rails test` run boots the app
    # before this file loads, so initializers have already connected to DB 0.
    REDIS_BASE_URL = ENV.fetch("TEST_REDIS_URL", "redis://localhost:6379/2")
    REDIS_MIN_DB   = 2
    REDIS_MAX_DB   = 15

    def self.connect_test_redis(db)
      raise "Test Redis DB #{db} out of range #{REDIS_MIN_DB}..#{REDIS_MAX_DB}" unless db.between?(REDIS_MIN_DB, REDIS_MAX_DB)

      url = REDIS_BASE_URL.sub(%r{/\d+\z}, "/#{db}")
      $redis = Redis.new(url:)
      Sidekiq.configure_client { _1.redis = { url: } }
    end

    connect_test_redis(REDIS_BASE_URL[%r{/(\d+)\z}, 1].to_i)

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Each worker has its own test database whose ids start at 1, so keys such as
    # "rate:<user_id>" collide across workers unless each worker also gets its own Redis DB.
    parallelize_setup { |worker| connect_test_redis(REDIS_MIN_DB + worker) }

    setup do
      db = $redis.connection[:db]
      raise "Refusing to flush Redis DB #{db}: not a test DB" if db < REDIS_MIN_DB

      $redis.flushdb
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
