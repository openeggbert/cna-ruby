# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"

# `plan.md`'s "Deferred boundaries" section, checked against the generated inventory it describes.
#
# This is the third staleness guard this project has needed and it is the same defect all three
# times: a document that states measured facts, next to a tool that measures them, with nothing
# comparing the two. The dependency frontier stayed stale for a whole milestone; the behaviour
# corpus's per-milestone value files drifted from the aggregate; and this section named
# `VertexDeclaration`, the four graphics state objects, `SpriteFont`, `ResourceContentManager` and
# `VideoPlayer` as absent for milestones after each was complete.
#
# The rule is narrow on purpose: prose may say more than the inventory, but it may not **contradict**
# it. Naming a complete type as absent is a contradiction; not naming an absent one is an editorial
# choice about which of eighty to list.
class PlanBoundariesTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path
  PLAN = ROOT.join("plan.md").read.freeze
  INVENTORY = ROOT.join("docs", "generated", "missing-type-inventory.md").read.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze

  SECTION = PLAN[/^## Deferred boundaries$.*/m].freeze
  # The delimited list, which is the only part of the section this guard reads. Prose around it may
  # name a complete type — it has to, to say that it is complete — and the delimiters are what keeps
  # "the list of absent types" a machine-readable claim rather than an English one.
  ABSENT = PLAN[/<!-- absent-types:begin -->(.*?)<!-- absent-types:end -->/m, 1].to_s.freeze

  # A nested type's leaf is its own: `…ModelBoneCollection+Enumerator` leafs to
  # `ModelBoneCollection+Enumerator`. `ContentTypeReader`1` keeps its backtick-arity suffix, which is
  # why the inventory is parsed by stripping the fence rather than by a non-greedy match.
  def self.leaf(name) = name.split(".").last

  def missing_types
    INVENTORY.lines.filter_map do |line|
      line.match(/\A- `(.+)`\s*\z/) { |match| match[1] }
    end
  end

  def complete_types = STRICT.fetch("completeTypeNames")

  def test_the_inventory_and_the_strict_report_agree
    assert_equal STRICT.fetch("MISSING_TYPES"), missing_types.length
    assert_empty missing_types & complete_types
  end

  def listed_absent = ABSENT.scan(/`([^`\s]+(?:`\d+)?)`/).flatten.uniq

  def test_the_delimited_list_exists_and_is_not_empty
    refute_empty ABSENT.strip, "plan.md must delimit its absent-type list for this guard to read"
    assert_operator listed_absent.length, :>, 40
  end

  # The guard, in both directions. Every name in the delimited list must be a type the strict report
  # calls missing, and no name in it may be one the strict report calls complete.
  def test_every_name_in_the_absent_list_is_really_missing
    missing_leaves = missing_types.map { |name| self.class.leaf(name) }
    assert_empty listed_absent - missing_leaves,
                 "plan.md lists types the missing-type inventory does not"
  end

  def test_no_complete_type_appears_in_the_absent_list
    complete_leaves = complete_types.map { |name| self.class.leaf(name) }
    assert_empty listed_absent & complete_leaves,
                 "plan.md's absent list names types the strict report calls complete"
  end

  # A guard nobody has seen fail is not evidence: the same rule, run against a list with one
  # complete type planted in it, must complain.
  def test_the_guard_fails_on_a_planted_complete_type
    planted = listed_absent + [self.class.leaf(complete_types.fetch(0))]
    missing_leaves = missing_types.map { |name| self.class.leaf(name) }
    complete_leaves = complete_types.map { |name| self.class.leaf(name) }
    refute_empty planted - missing_leaves
    refute_empty planted & complete_leaves
  end

  # The partial remainder is quoted in words, so it has to move when the scoreboard does.
  def test_the_quoted_partial_remainders_match_the_scoreboard
    partial = STRICT.fetch("partialTypes")
    device = partial.fetch("Microsoft.Xna.Framework.Graphics.GraphicsDevice")
    manager = partial.fetch("Microsoft.Xna.Framework.GraphicsDeviceManager")
    assert_equal 23, device.length
    assert_equal 15, manager.length
    assert_equal 2, partial.length, "SpriteBatch left when the Effect cluster landed"
    flat = SECTION.gsub(/\s+/, " ")
    assert_includes flat, "owes twenty-three members"
    assert_includes flat, "`GraphicsDeviceManager` fifteen"
    assert_includes flat, "they are the only two partial types left"
  end
end
