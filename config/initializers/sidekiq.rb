# frozen_string_literal: true

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

  # Advertised in Sidekiq::ProcessSet so load tests can refuse to enqueue against a worker
  # that would call the real LLM. After boot, because LlmClient is autoloaded.
  Rails.application.config.after_initialize do
    config[:labels] << LlmClient::MOCK_LABEL if LlmClient.mock?
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end
