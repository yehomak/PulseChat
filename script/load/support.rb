# frozen_string_literal: true

# Shared seeding for script/load/*. Only ever touches users whose email starts with "load_".
module LoadSupport
  EMAIL_PREFIX = "load_"
  BATCH        = 10_000

  module_function

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
