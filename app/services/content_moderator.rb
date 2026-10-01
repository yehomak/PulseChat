# frozen_string_literal: true

# Keyword guard against insults aimed at the companion. Terms are chosen to be near-unambiguous:
# words like "broke", "npc" or "clown" are deliberately absent, since blocking "my build broke"
# or "the NPCs in this game" costs more than it catches. General profanity is allowed. A keyword
# list is a first line only; misspellings and paraphrase need a classifier.
class ContentModerator
  BLACKLIST = [
    "dumbass",
    "dumb ass",
    "dipshit",
    "jackass",
    "dickhead",
    "shithead",
    "asshole",
    "moron",
    "idiot",
    "imbecile"
  ].to_set.freeze

  # Whole words only (so "idiotic" and "moronic" pass), optional plural, case-insensitive.
  # Spaces inside a phrase also match hyphens: "dumb ass" catches "dumb-ass".
  PATTERN = begin
    terms = BLACKLIST.sort_by { -_1.length }.map { Regexp.escape(_1).gsub("\\ ", "[\\s-]+") }
    /\b(?:#{terms.join("|")})s?\b/i
  end

  def self.blocked?(text)
    PATTERN.match?(text.to_s)
  end
end
