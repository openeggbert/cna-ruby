# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require_relative "../tools/scoreboard"

# The staleness guard for `plan.md` and `NEXT.md`.
#
# This project has now found the same defect five times: a document stating a measured fact, beside
# a tool that measures it, with **nothing comparing the two**. The dependency frontier stayed stale
# for a milestone; the behaviour corpus's per-milestone value files drifted from the aggregate;
# `plan.md`'s "Deferred boundaries" list named five complete types as absent; `NEXT.md`'s "Measured
# state" went eleven milestones out of date; and `plan.md`'s "Surface" section described a
# 177-type / 2152-identity surface while the verifier was measuring 200 / 2372 and had been for
# eleven milestones. Each of the first four was fixed by writing a guard. This is the fifth guard,
# and it closes the general case rather than one section.
#
# Three rules, in increasing strength:
#
# 1. **The generated block is byte-exact.** Both documents carry
#    `<!-- scoreboard:begin -->…<!-- scoreboard:end -->`, and it must equal what `tools/scoreboard.rb`
#    renders from the live reports right now.
#
# 2. **Every claim regex must match, and every match must be right.** A claim that no longer matches
#    fails just as loudly as one that matches a stale number, so the guard cannot be defeated by
#    rewording the sentence it watches.
#
# 3. **`plan.md` may not contain a numeral no fact accounts for.** That is the rule the first two
#    cannot give: it makes adding a *new* stale number impossible rather than merely making the
#    known ones checkable. `plan.md` is the normative document — "this file is what is true of it
#    now" — so a count in it is always a claim about current state. `NEXT.md` is chronological and
#    is deliberately exempt from the sweep: its milestone table is history, and history keeps its
#    numbers.
class DocumentScoreboardTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path
  PLAN = ROOT.join("plan.md").read.freeze
  NEXT = ROOT.join("NEXT.md").read.freeze

  # ------------------------------------------------------------------ 1. the generated block

  def test_plan_carries_the_generated_block_and_it_is_current
    assert_equal CNAScoreboard.block, CNAScoreboard.extract(PLAN),
                 "plan.md's scoreboard is stale; run `ruby tools/render_scoreboard.rb`"
  end

  def test_next_carries_the_generated_block_and_it_is_current
    assert_equal CNAScoreboard.block, CNAScoreboard.extract(NEXT),
                 "NEXT.md's scoreboard is stale; run `ruby tools/render_scoreboard.rb`"
  end

  def test_every_fact_reaches_the_rendered_block
    rendered = CNAScoreboard.block
    CNAScoreboard.facts.each do |fact|
      assert_includes rendered, "| #{fact.value} | #{fact.label} |", "#{fact.key} is not rendered"
    end
  end

  # A guard nobody has seen fail is not evidence. Mutating one report value must move the block.
  def test_the_block_moves_when_a_report_value_moves
    original = CNAScoreboard.facts
    mutated = original.map { |fact| fact.key == "COMPLETE_TYPES" ? fact.dup.tap { |copy| copy.value += 1 } : fact }
    CNAScoreboard.instance_variable_set(:@facts, mutated)
    refute_equal CNAScoreboard.extract(PLAN), CNAScoreboard.block
  ensure
    CNAScoreboard.instance_variable_set(:@facts, original)
  end

  def test_rewrite_is_idempotent_and_refuses_a_document_without_markers
    assert_equal PLAN, CNAScoreboard.rewrite(PLAN)
    assert_raises(ArgumentError) { CNAScoreboard.rewrite("no markers here") }
    assert_raises(ArgumentError) { CNAScoreboard.extract("no markers here") }
  end

  # ------------------------------------------------------------------ 2. prose claims
  #
  # Each entry watches one sentence. The capture group is the number the sentence states; the fact
  # key is what it must equal. `words` marks a claim written out in English rather than in digits.
  Claim = Struct.new(:document, :fact, :pattern, :words, keyword_init: true)

  WORD_NUMBERS = {
    "zero" => 0, "one" => 1, "two" => 2, "three" => 3, "four" => 4, "five" => 5, "six" => 6,
    "seven" => 7, "eight" => 8, "nine" => 9, "ten" => 10, "eleven" => 11, "twelve" => 12,
    "thirteen" => 13, "fourteen" => 14, "fifteen" => 15, "sixteen" => 16, "seventeen" => 17,
    "eighteen" => 18, "nineteen" => 19, "twenty" => 20
  }.freeze

  CLAIMS = [
    Claim.new(document: :plan, fact: "PARTIAL_TYPES", words: true,
              pattern: /\bthe (\w+) partial runtime types\b/),
    Claim.new(document: :next, fact: "PARTIAL_TYPES", words: true,
              pattern: /\bare the (\w+) partial types\b/)
  ].freeze

  def document(which) = which == :plan ? PLAN : NEXT

  def test_every_claim_still_matches_its_sentence
    CLAIMS.each do |claim|
      assert_match claim.pattern, document(claim.document),
                   "#{claim.document}.md no longer carries the sentence guarding #{claim.fact}; " \
                   "reword the claim or drop it, but do not leave it unwatched"
    end
  end

  def test_every_claim_states_the_measured_number
    CLAIMS.each do |claim|
      document(claim.document).scan(claim.pattern) do |(captured)|
        stated = claim.words ? WORD_NUMBERS.fetch(captured.downcase) : Integer(captured.delete(","))
        assert_equal CNAScoreboard.value(claim.fact), stated,
                     "#{claim.document}.md states #{captured.inspect} where #{claim.fact} is " \
                     "#{CNAScoreboard.value(claim.fact)}"
      end
    end
  end

  # Two plantings, because a claim can rot in two directions. A wrong number must fail the value
  # check while still matching; a reworded sentence must fail the match check.
  def test_the_claim_check_fails_on_a_planted_stale_number
    claim = CLAIMS.first
    planted = document(claim.document).sub(claim.pattern) { "the seven partial runtime types" }
    stated = planted.match(claim.pattern)[1]
    assert_equal "seven", stated
    refute_equal CNAScoreboard.value(claim.fact), WORD_NUMBERS.fetch(stated)
  end

  def test_the_claim_check_fails_on_a_reworded_sentence
    claim = CLAIMS.first
    reworded = document(claim.document).sub(claim.pattern) { "the partial runtime types" }
    refute_match claim.pattern, reworded
  end

  # ------------------------------------------------------------------ 3. the numeral sweep

  # Numerals in `plan.md` that are not counts of anything this project measures. Each is a literal
  # from the environment or from a name, and each is listed with what it is. The test requires every
  # one of them to still occur, so an entry cannot quietly rot into a licence for a stale count.
  LITERAL_NUMERALS = {
    "6" => "Native frontier 6, a milestone's name",
    "44100" => "the mixer's sample rate in Hz",
    "103" => "Foundation 103, a milestone's name -- the one that recorded Song's blocker",
    "104" => "Foundation 104, a milestone's name -- the one that measured it false"
  }.freeze

  # A sentinel the sweep must still be able to see. Stripping code spans is itself a scanner, and
  # this project has found four defects that were all one scanner losing a token boundary — so the
  # stripper is checked against a numeral it must never swallow.
  SWEEP_SENTINEL = "44100"

  # Code spans are stripped **within one line**. A document-wide backtick scan is what over-strips:
  # `plan.md` carries an odd number of backticks, so a naive `/`[^`]*`/` pairs across sentences and
  # silently deletes whole paragraphs — including the sentinel above. Confining the search to the
  # line bounds the damage of any mispairing to that line, which is the same "bound the token on
  # both sides" rule the numeral scanner below follows.
  def self.strip_code_spans(line)
    out = +""
    index = 0
    while (open = line.index("`", index))
      out << line[index...open]
      run = line[open..].match(/\A`+/)[0]
      close = line.index(run, open + run.length)
      if close
        out << " "
        index = close + run.length
      else
        out << run
        index = open + run.length
      end
    end
    out << line[index..].to_s
  end

  # Fenced code, the generated block, HTML comments and inline code spans carry names, commands and
  # symbols rather than claims, so the sweep does not read them.
  def plan_prose
    text = PLAN.sub(/#{Regexp.escape(CNAScoreboard::BEGIN_MARK)}.*?#{Regexp.escape(CNAScoreboard::END_MARK)}/m, "")
    text = text.gsub(/^```.*?^```/m, "")
    text = text.gsub(/<!--.*?-->/m, "")
    text.each_line.map { |line| self.class.strip_code_spans(line) }.join
  end

  # Bounded on both sides — the rule four measurement defects in this project were caused by
  # breaking. A digit run must not be preceded or followed by another digit, a letter (which is what
  # excludes `1280x800`), or the `.` `-` `/` that make a version, a hyphenated compound or a
  # `Vector2/3/4`.
  def numerals(text) = text.scan(%r{(?<![\w./-])(\d+)(?![\w./-])}).flatten

  def test_the_sweep_reads_something
    refute_empty plan_prose.strip
    refute_includes plan_prose, CNAScoreboard::BEGIN_MARK
    assert_includes plan_prose, SWEEP_SENTINEL, "the code-span stripper swallowed prose it must keep"
    assert_operator plan_prose.length, :>, PLAN.length / 2,
                    "the code-span stripper removed more than half the document; it has mispaired"
  end

  def test_no_numeral_in_plan_is_unaccounted_for
    accounted = CNAScoreboard.facts.map { |fact| fact.value.to_s }.to_set
    claimed = CLAIMS.select { |claim| claim.document == :plan && !claim.words }
                    .flat_map { |claim| plan_prose.scan(claim.pattern).flatten }
                    .to_set
    unaccounted = numerals(plan_prose).uniq.reject do |numeral|
      LITERAL_NUMERALS.key?(numeral) || accounted.include?(numeral) || claimed.include?(numeral)
    end
    assert_empty unaccounted,
                 "plan.md states numerals no scoreboard fact accounts for: #{unaccounted.join(", ")}. " \
                 "Either the number is a measurement — give it a fact in tools/scoreboard.rb and let " \
                 "the generated block carry it — or it is a literal, and belongs in LITERAL_NUMERALS " \
                 "with what it is."
  end

  def test_every_literal_numeral_still_occurs
    present = numerals(plan_prose).to_set
    stale = LITERAL_NUMERALS.keys.reject { |numeral| present.include?(numeral) }
    assert_empty stale, "LITERAL_NUMERALS names numerals plan.md no longer contains: #{stale.join(", ")}"
  end

  def test_the_sweep_fails_on_a_planted_stale_count
    planted = plan_prose + "\n\nThe strict surface is 177 types across 2152 member identities.\n"
    accounted = CNAScoreboard.facts.map { |fact| fact.value.to_s }.to_set
    unaccounted = numerals(planted).uniq.reject do |numeral|
      LITERAL_NUMERALS.key?(numeral) || accounted.include?(numeral)
    end
    assert_includes unaccounted, "177"
    assert_includes unaccounted, "2152"
  end

  # The boundary rule itself, since three of this project's four measurement defects were a scanner
  # anchored on one side of a token.
  def test_the_numeral_scanner_is_bounded_on_both_sides
    assert_equal %w[42], numerals("a count of 42 things")
    assert_empty numerals("Texture2D and OPENGL33 and 0x1500")
    assert_empty numerals("version 0.21.0 and 1280x800 and the 19-type closure")
    assert_empty numerals("MathHelper, Vector2/3/4, Quaternion")
    assert_equal %w[7], numerals("(7)")
  end

  def test_the_code_span_stripper_keeps_the_line_it_cannot_pair
    stripped = self.class.strip_code_spans("once `System.Char`, ``Nullable`1`` and `StringBuilder` were decided\n")
    assert_includes stripped, "were decided"
    assert_empty numerals(stripped)
    # An unclosed run is emitted rather than treated as opening a span that runs off the line.
    assert_includes self.class.strip_code_spans("a stray ` and the count 42\n"), "42"
  end
end
