# frozen_string_literal: true

# Demo account for local evaluation. Development only: a known password must never exist in production.
if Rails.env.development?
  demo = User.find_or_create_by!(email_address: "demo@pulsechat.dev") do |user|
    user.password = "pulsechat-demo"
  end
  demo.conversations.find_or_create_by!(title: "Welcome")

  puts "Demo login: demo@pulsechat.dev / pulsechat-demo"
end
