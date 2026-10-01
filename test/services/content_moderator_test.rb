# frozen_string_literal: true

require "test_helper"

class ContentModeratorTest < ActiveSupport::TestCase
  test "blocks a message containing a blacklisted word" do
    assert ContentModerator.blocked?("you're such a dumbass")
  end

  test "matching is case-insensitive" do
    assert ContentModerator.blocked?("DUMBASS")
    assert ContentModerator.blocked?("Moron")
  end

  test "does not match blacklisted words inside other words" do
    assert_not ContentModerator.blocked?("that was an idiotic bug")
    assert_not ContentModerator.blocked?("a moronic plot twist")
  end

  test "passes everyday words that look like slang insults" do
    assert_not ContentModerator.blocked?("my build broke and I'm broke this month")
    assert_not ContentModerator.blocked?("the NPCs in this game are great, what a clown fiesta")
  end

  test "allows general profanity that isn't an insult" do
    assert_not ContentModerator.blocked?("holy shit that's a good joke")
  end

  test "matches plurals and hyphenated or spaced phrases" do
    assert ContentModerator.blocked?("idiots")
    assert ContentModerator.blocked?("what a dumb-ass take")
    assert ContentModerator.blocked?("dumb   ass")
  end

  test "treats nil as clean" do
    assert_not ContentModerator.blocked?(nil)
  end
end
