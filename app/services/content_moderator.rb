# frozen_string_literal: true

# Keyword guard against sexual content involving minors. Terms are chosen to be near-unambiguous
# in an adult companion chat: everyday words like "child", "kid" or "minor" are deliberately
# absent, since blocking "I miss my children" costs more than it catches. A keyword list is a
# first line only; misspellings and paraphrase need a classifier.
class ContentModerator
  BLACKLIST = [
    "underage",
    "preteen",
    "pre teen",
    "jailbait",
    "loli",
    "lolicon",
    "shota",
    "shotacon",
    "pedo",
    "pedophile",
    "paedophile",
    "pedophilia",
    "paedophilia",
    "csam",
    "child porn",
    "child pornography",
    "kiddie porn",
    "child sex"
  ].to_set.freeze

  # Whole words only (so "torpedo" and "lollipop" pass), optional plural, case-insensitive.
  # Spaces inside a phrase also match hyphens: "pre teen" catches "pre-teen".
  PATTERN = begin
    terms = BLACKLIST.sort_by { -_1.length }.map { Regexp.escape(_1).gsub("\\ ", "[\\s-]+") }
    /\b(?:#{terms.join("|")})s?\b/i
  end

  def self.blocked?(text)
    PATTERN.match?(text.to_s)
  end
end
