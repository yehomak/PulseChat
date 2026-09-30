# frozen_string_literal: true

# Measures the async pipeline (Sidekiq -> LlmInferenceJob -> DB -> broadcast), bypassing HTTP.
#
#   SCENARIO=spread  USERS=100 PER_USER=10  bin/rails runner script/load/pipeline.rb
#   SCENARIO=history USERS=50  SIZE=10000   bin/rails runner script/load/pipeline.rb
#
# Sidekiq must already be running with LLM_MOCK=1 (see docs/load_test.md).
# Only touches users whose email starts with "load_"; they are wiped at the start of every run.

require "sidekiq/api"
require_relative "support"

$stdout.sync = true

module LoadTest
  DONE = %w[completed failed cancelled].freeze

  module_function

  def run
    scenario = ENV.fetch("SCENARIO", "spread")
    timeout  = ENV.fetch("TIMEOUT", "900").to_i

    preflight!
    LoadSupport.cleanup!

    message_ids =
      case scenario
      when "spread"  then seed_spread(users: int("USERS", 100), per_user: int("PER_USER", 10))
      when "history" then seed_history(users: int("USERS", 50), size: int("SIZE", 1000))
      else abort "Unknown SCENARIO=#{scenario}"
      end

    puts "Enqueueing #{message_ids.size} jobs..."
    ActiveJob.perform_all_later(message_ids.map { LlmInferenceJob.new(_1) })

    wait_for(message_ids, timeout:)
    verify_mock!(message_ids)
    report(scenario, message_ids)
  end

  def int(key, default) = ENV.fetch(key, default.to_s).to_i

  def preflight!
    LoadSupport.require_mocked_workers!

    backlog = Sidekiq::Queue.new("llm").size + Sidekiq::RetrySet.new.size + Sidekiq::ScheduledSet.new.size
    abort "llm queue / retry / scheduled sets not empty (#{backlog}). Clear them for a clean run." if backlog.positive?
  end

  def pending_rows(conversation_ids, per_conversation)
    now = Time.current
    conversation_ids.flat_map do |cid|
      Array.new(per_conversation) do |i|
        { conversation_id: cid, role: 0, status: 0, content: "Load message #{i}", created_at: now, updated_at: now }
      end
    end
  end

  def insert_pending(conversation_ids, per_conversation)
    Message.insert_all!(pending_rows(conversation_ids, per_conversation), returning: :id).rows.flatten
  end

  def seed_spread(users:, per_user:)
    puts "Seeding spread: #{users} users x #{per_user} messages"
    insert_pending(LoadSupport.seed_users(users).map(&:last), per_user)
  end

  # Pre-fills each conversation with SIZE completed messages so build_history has real work to do.
  def seed_history(users:, size:)
    puts "Seeding history: #{users} users, #{size} prior messages each"
    conversation_ids = LoadSupport.seed_users(users).map(&:last)
    base = 1.day.ago

    conversation_ids.each do |cid|
      rows = Array.new(size) do |i|
        at = base + i.seconds
        { conversation_id: cid, role: i % 2, status: 2, content: "History #{i}", created_at: at, updated_at: at }
      end
      rows.each_slice(LoadSupport::BATCH) { Message.insert_all!(_1) }
    end

    insert_pending(conversation_ids, 1)
  end

  def wait_for(message_ids, timeout:)
    started = monotonic
    total   = message_ids.size

    loop do
      done = Message.where(id: message_ids, status: DONE).count
      print "\r  #{done}/#{total} done  (#{(monotonic - started).round(1)}s)"
      break puts if done == total

      if monotonic - started > timeout
        puts
        abort "Timed out after #{timeout}s with #{total - done} jobs unfinished"
      end
      sleep 0.5
    end
  end

  # Guards against a Sidekiq started without LLM_MOCK=1 silently calling the real provider.
  def verify_mock!(message_ids)
    if Message.where(id: message_ids, status: "completed").none?
      abort "No jobs completed. Check the Sidekiq log; it was probably started without LLM_MOCK=1."
    end

    conversation_ids = Message.where(id: message_ids).distinct.pluck(:conversation_id)
    sample = Message.where(conversation_id: conversation_ids, role: 1, status: 2)
                    .where.not("content LIKE 'History %'").pick(:content)
    return if sample.nil? || sample == LlmClient::MOCK_REPLY

    abort "Assistant replies are not mocked (got #{sample.truncate(40).inspect}). Restart Sidekiq with LLM_MOCK=1."
  end

  def report(scenario, message_ids)
    scope     = Message.where(id: message_ids)
    completed = scope.where(status: "completed")
    latencies = completed.pluck(Arel.sql("EXTRACT(EPOCH FROM (updated_at - created_at))")).map(&:to_f).sort
    first_at, last_at = scope.pick(Arel.sql("MIN(created_at)"), Arel.sql("MAX(updated_at)"))
    drain = (last_at - first_at).to_f

    puts <<~REPORT

      == #{scenario} #{ENV.slice("USERS", "PER_USER", "SIZE").map { "#{_1}=#{_2}" }.join(" ")}
      mock latency     #{(LlmClient.mock_latency_seconds * 1000).round}ms (runner's view; Sidekiq's ENV must match)
      jobs             #{message_ids.size} (completed #{latencies.size}, failed #{scope.where(status: "failed").count})
      drain time       #{drain.round(2)}s
      throughput       #{(latencies.size / drain).round(2)} jobs/s
      latency p50      #{pct(latencies, 0.50)}s
      latency p95      #{pct(latencies, 0.95)}s
      latency max      #{latencies.last&.round(2)}s
    REPORT
  end

  def pct(sorted, p)
    return "-" if sorted.empty?

    sorted[((sorted.size - 1) * p).round].round(2)
  end

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

# rails runner enables the query cache, which would freeze the polling count at its first value.
ActiveRecord::Base.uncached { LoadTest.run }
