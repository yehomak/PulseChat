# frozen_string_literal: true

class LlmInferenceJob < ApplicationJob
  queue_as :llm

  # ActiveJob's retry_on is the only retry layer; a second Sidekiq layer would re-run failed jobs.
  sidekiq_options queue: :llm, retry: 0

  # Worth retrying: the provider or database may succeed on a later attempt.
  TRANSIENT_ERRORS = [
    Faraday::ServerError,          # 5xx and timeouts
    Faraday::ConnectionFailed,
    Faraday::TooManyRequestsError, # 429
    ActiveRecord::Deadlocked,
    ActiveRecord::ConnectionTimeoutError
  ].freeze

  # Handlers are matched last-declared-first, so the catch-all comes first.
  discard_on(StandardError) { |job, error| job.fail_message(error) }
  retry_on(*TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: 3) { |job, error| job.fail_message(error) }
  discard_on ActiveRecord::RecordNotFound

  def perform(message_id)
    ChatReplyService.call(Message.find(message_id))
  end

  # Runs once retries are exhausted or the error is not worth retrying. While retries are
  # pending the message stays "streaming", so the user sees it is still being worked on.
  def fail_message(error)
    Rails.error.report(error, handled: true, context: { job: self.class.name, message_id: arguments.first })

    message = Message.find_by(id: arguments.first)
    return if message.nil? || message.finished?

    message.update!(status: :failed)
    broadcast_status(message)
  end

  private

  def broadcast_status(message)
    Turbo::StreamsChannel.broadcast_replace_to(
      message.conversation,
      target:  ActionView::RecordIdentifier.dom_id(message),
      partial: "messages/message",
      locals:  { message: message, conversation: message.conversation }
    )
  rescue => e
    Rails.logger.error("LlmInferenceJob status broadcast error: #{e.class} #{e.message}")
  end
end
