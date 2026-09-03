# frozen_string_literal: true

require_relative "scoreboard"

# Rewrites the delimited scoreboard block in every document that carries one.
#
#     ruby tools/render_scoreboard.rb           # rewrite in place
#     ruby tools/render_scoreboard.rb --check    # exit 1 if any document is stale
#
# `test/test_document_scoreboard.rb` performs the same comparison, so the check mode is for running
# the repair by hand after regenerating the reports.
DOCUMENTS = %w[plan.md NEXT.md].freeze

check = ARGV.delete("--check")
stale = []

DOCUMENTS.each do |name|
  path = File.join(CNAScoreboard::ROOT, name)
  text = File.read(path)
  rewritten = CNAScoreboard.rewrite(text)
  if rewritten == text
    puts "#{name}: current"
    next
  end

  stale << name
  if check
    puts "#{name}: STALE"
  else
    File.write(path, rewritten)
    puts "#{name}: rewritten"
  end
end

puts "SCOREBOARD_FACTS=#{CNAScoreboard.facts.length}"
puts "STALE_DOCUMENTS=#{stale.length}"
exit 1 if check && !stale.empty?
