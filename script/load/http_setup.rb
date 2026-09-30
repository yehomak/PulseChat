# frozen_string_literal: true

# Prepares authenticated users for the k6 HTTP load test (script/load/http.js).
#
#   USERS=100 BASE_URL=http://localhost:3000 bin/rails runner script/load/http_setup.rb
#
# Puma and a Sidekiq started with LLM_MOCK=1 must be running.
# Sessions are created directly rather than via POST /session, because SessionsController
# rate-limits logins to 10 per 3 minutes per IP and every load user shares one.
# Each user then does a real GET of its conversation: that proves the cookie authenticates and
# yields the CSRF token plus the Rails session cookie it is bound to.

require "net/http"
require "sidekiq/api"
require_relative "support"

$stdout.sync = true

module HttpSetup
  OUTPUT = Rails.root.join("tmp/load/users.json")

  module_function

  def run
    base_url = URI(ENV.fetch("BASE_URL", "http://localhost:3000"))
    count    = ENV.fetch("USERS", "100").to_i

    LoadSupport.require_mocked_workers!
    LoadSupport.cleanup!
    pairs = LoadSupport.seed_users(count)
    puts "Seeded #{pairs.size} users, authenticating against #{base_url}..."

    users = Net::HTTP.start(base_url.host, base_url.port) do |http|
      pairs.map { |user_id, conversation_id| authenticate(http, user_id, conversation_id) }
    end

    FileUtils.mkdir_p(OUTPUT.dirname)
    File.write(OUTPUT, JSON.pretty_generate(users))
    puts "Wrote #{users.size} users to #{OUTPUT.relative_path_from(Rails.root)}"
  end

  def authenticate(http, user_id, conversation_id)
    session_cookie = "session_id=#{Rack::Utils.escape(signed_session_id(user_id))}"
    response = http.get("/conversations/#{conversation_id}", "Cookie" => session_cookie)

    unless response.is_a?(Net::HTTPOK)
      abort "GET /conversations/#{conversation_id} returned #{response.code} " \
            "(#{response["Location"] || "no redirect"}). Is the server running in development?"
    end

    csrf = response.body[/<meta name="csrf-token" content="([^"]+)"/, 1] or abort "No CSRF token in page"
    rails_session = response.get_fields("Set-Cookie").to_a.map { _1.split(";").first }

    { user_id:, conversation_id:, csrf:, cookie: [ session_cookie, *rails_session ].join("; ") }
  end

  # Same cookie start_new_session_for sets, signed with the app's key.
  def signed_session_id(user_id)
    session = Session.create!(user_id:, user_agent: "k6-load-test", ip_address: "127.0.0.1")
    jar = ActionDispatch::Request.new(Rails.application.env_config.merge("HTTP_HOST" => "localhost")).cookie_jar
    jar.signed[:session_id] = session.id
    jar[:session_id]
  end
end

HttpSetup.run
