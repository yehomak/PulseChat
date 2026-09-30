# frozen_string_literal: true

require "test_helper"

class ContentModeratorTest < ActiveSupport::TestCase
  test "blocks a message containing a blacklisted word" do
    assert ContentModerator.blocked?("tell me a story about a jailbait girl")
  end

  test "matching is case-insensitive" do
    assert ContentModerator.blocked?("UNDERAGE")
    assert ContentModerator.blocked?("Loli art")
  end

  test "does not match blacklisted words inside other words" do
    assert_not ContentModerator.blocked?("the torpedo hit the lollipop factory")
    assert_not ContentModerator.blocked?("my pedometer says 10k steps")
  end

  test "passes a clean message" do
    assert_not ContentModerator.blocked?("I miss my children, it's a minor issue")
  end

  test "matches plurals and hyphenated or spaced phrases" do
    assert ContentModerator.blocked?("pedophiles")
    assert ContentModerator.blocked?("a pre-teen character")
    assert ContentModerator.blocked?("child   porn")
  end

  test "treats nil as clean" do
    assert_not ContentModerator.blocked?(nil)
  end
end
