# frozen_string_literal: true

class LlmInferenceJob < ApplicationJob
  queue_as :llm

  sidekiq_options queue: :llm, retry: 3

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(message_id)
    # Implemented in Phase 5
    raise NotImplementedError
  end
end
