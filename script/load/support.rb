# frozen_string_literal: true

# Shared seeding for script/load/*. Only ever touches users whose email starts with "load_".
module LoadSupport
  EMAIL_PREFIX = "load_"
  BATCH        = 10_000

  module_function

  # Runs before anything is seeded or enqueued: a worker without LLM_MOCK=1 would send every
  # load message to the real provider on the real key. Workers advertise mock mode as a
  # Sidekiq label (config/initializers/sidekiq.rb), so this check costs zero LLM calls.
  def require_mocked_workers!
    workers = Sidekiq::ProcessSet.new.select { _1["queues"].include?("llm") }
    abort "No Sidekiq process serves the llm queue. Start one with LLM_MOCK=1." if workers.empty?

    workers.each do |p|
      mocked = p["labels"].include?(LlmClient::MOCK_LABEL)
      puts "Sidekiq pid=#{p["pid"]} concurrency=#{p["concurrency"]} llm=#{mocked ? "mock" : "LIVE"}"
    end

    live = workers.reject { _1["labels"].include?(LlmClient::MOCK_LABEL) }
    return if live.empty?

    abort "Refusing to run: Sidekiq pid #{live.map { _1["pid"] }.join(", ")} would call the real LLM. " \
          "Restart it with LLM_MOCK=1 (and without sourcing .env)."
  end

  def cleanup!
    user_ids = User.where("email_address LIKE ?", "#{EMAIL_PREFIX}%").ids
    return if user_ids.empty?

    conversation_ids = Conversation.where(user_id: user_ids).ids
    Message.where(conversation_id: conversation_ids).in_batches(of: BATCH).delete_all
    Conversation.where(id: conversation_ids).delete_all
    Session.where(user_id: user_ids).delete_all
    User.where(id: user_ids).delete_all
    $redis.del(*user_ids.map { "rate:#{_1}" })
    puts "Cleaned up #{user_ids.size} previous load users"
  end

  # Returns [[user_id, conversation_id], ...], one conversation per user.
  def seed_users(count)
    digest = BCrypt::Password.create("password", cost: BCrypt::Engine::MIN_COST)
    now    = Time.current
    rows   = Array.new(count) do |i|
      { email_address: "#{EMAIL_PREFIX}#{i}@example.com", password_digest: digest, created_at: now, updated_at: now }
    end
    user_ids = User.insert_all!(rows, returning: :id).rows.flatten

    conv_rows = user_ids.map { { user_id: _1, title: "Load test", created_at: now, updated_at: now } }
    user_ids.zip(Conversation.insert_all!(conv_rows, returning: :id).rows.flatten)
  end
end
