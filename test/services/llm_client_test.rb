# frozen_string_literal: true

require "test_helper"

class LlmClientTest < ActiveSupport::TestCase
  HISTORY = [ { role: "user", content: "Hello" } ].freeze

  def with_env(vars)
    previous = vars.keys.to_h { [ _1, ENV[_1] ] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| ENV[k] = v }
  end

  test "mock mode returns canned content and token count" do
    with_env("LLM_MOCK" => "1", "LLM_MOCK_LATENCY_MS" => "0") do
      assert_equal [ LlmClient::MOCK_REPLY, LlmClient::MOCK_TOKENS ], LlmClient.chat(HISTORY)
    end
  end

  test "mock mode sleeps for configured latency" do
    slept = nil

    with_env("LLM_MOCK" => "1", "LLM_MOCK_LATENCY_MS" => "250") do
      LlmClient.stub(:sleep, ->(seconds) { slept = seconds }) { LlmClient.chat(HISTORY) }
    end

    assert_in_delta 0.25, slept
  end

  test "live mode calls provider with history and parses the response" do
    response = {
      "choices" => [ { "message" => { "content" => "Live reply" } } ],
      "usage"   => { "completion_tokens" => 7 }
    }
    provider = Minitest::Mock.new
    provider.expect(:chat, response) do |parameters:|
      parameters == { model: LlmClient::MODEL, messages: HISTORY, max_tokens: LlmClient::MAX_TOKENS }
    end

    build_client = lambda do |access_token:, uri_base:|
      assert_equal "test-key", access_token
      assert_equal LlmClient::URI_BASE, uri_base
      provider
    end

    with_env("LLM_MOCK" => nil, "XAI_API_KEY" => "test-key") do
      OpenAI::Client.stub(:new, build_client) do
        assert_equal [ "Live reply", 7 ], LlmClient.chat(HISTORY)
      end
    end

    provider.verify
  end

  test "mock flag is ignored in production" do
    with_env("LLM_MOCK" => "1") do
      Rails.env.stub(:production?, true) { assert_not LlmClient.mock? }
    end
  end
end
