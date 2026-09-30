# frozen_string_literal: true

class LlmClient
  URI_BASE   = "https://api.groq.com/openai/v1"
  MODEL      = "qwen/qwen3.8-27b"
  MAX_TOKENS = 1000

  MOCK_REPLY  = "Mocked reply."
  MOCK_TOKENS = 10

  class << self
    def chat(history)
      mock? ? mock_chat : live_chat(history)
    end

    # Never in production: mocked replies are saved as real completed messages.
    def mock?
      ENV["LLM_MOCK"] == "1" && !Rails.env.production?
    end

    def mock_latency_seconds
      ENV.fetch("LLM_MOCK_LATENCY_MS", "1000").to_i / 1000.0
    end

    private

    def mock_chat
      sleep(mock_latency_seconds)
      [ MOCK_REPLY, MOCK_TOKENS ]
    end

    def live_chat(history)
      client = OpenAI::Client.new(access_token: ENV.fetch("XAI_API_KEY"), uri_base: URI_BASE)

      response = client.chat(
        parameters: { model: MODEL, messages: history, max_tokens: MAX_TOKENS }
      )

      content     = response.dig("choices", 0, "message", "content").to_s
      tokens_used = response.dig("usage", "completion_tokens").to_i

      [ content, tokens_used ]
    end
  end
end
