# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../tools/api_compat/signature_builder"

# `selection.json` is the reviewed statement of what this binding targets; `signatures.json` is what
# the verifier measures against. Nothing compared them, and they had diverged badly.
#
# When this guard was written, running `tools/api_compat/build_signatures.rb` would have **deleted
# 237 member identities and 23 whole types** from the measured target — `GameWindow`, `SpriteFont`,
# the six `Audio` XACT types, `ContentManager`, every `Texture2D` member past `Bounds`, every
# `SpriteBatch.DrawString` and destination-rectangle `Draw`, `GraphicsDeviceManager`'s eleven
# preferred settings — because those had been maintained only in the generated file. The strict
# scoreboard would have fallen from 174 complete types to 151 and nothing in the suite would have
# failed, because every test reads the generated file.
#
# This is the fourth artifact in this project to drift from the tool that claims to produce it. The
# other three each got a guard when they were found; this is that guard.
class SignatureSelectionTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path
  Builder = CNAApiCompat::SignatureBuilder

  CHECKED_IN = ROOT.join("tools", "api_compat", "signatures.json").read.freeze
  SELECTION = JSON.parse(ROOT.join("tools", "api_compat", "selection.json").read).freeze
  REFERENCE = JSON.parse(ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read).freeze

  # The whole guard, in one assertion: the generator's output is the checked-in file, byte for byte.
  def test_the_generator_reproduces_the_checked_in_signatures_exactly
    assert_equal CHECKED_IN, Builder.serialize(Builder.build),
                 "tools/api_compat/build_signatures.rb no longer reproduces signatures.json"
  end

  def test_every_selected_type_names_a_reference_type
    names = REFERENCE.fetch("types").map { |type| type.fetch("name") }
    selected = SELECTION.fetch("types").map { |type| type.fetch("name") }
    assert_empty selected - names
    assert_equal selected.length, selected.uniq.length
  end

  # A selection entry says either "all of it" or "exactly these"; anything else is a wildcard whose
  # meaning changes when the reference does.
  def test_every_entry_is_either_complete_or_an_explicit_include_list
    SELECTION.fetch("types").each do |type|
      assert_equal 2, type.keys.length, type.fetch("name")
      assert(type["complete"] || type["include"], type.fetch("name"))
      next unless type["include"]

      type.fetch("include").each do |selector|
        assert_equal %w[kind name parameters static], (selector.keys - ["override"]).sort,
                     "#{type.fetch("name")} selector #{selector.inspect} must be unambiguous"
      end
    end
  end

  # An `override` is how a deliberate deviation from the reference is *declared* rather than
  # smuggled in, and the verifier reports it. There is exactly one, and the strict report counts it.
  def test_the_only_declared_override_is_the_one_the_scoreboard_reports
    overrides = SELECTION.fetch("types").flat_map do |type|
      type.fetch("include", []).select { |selector| selector["override"] }
          .map { |selector| ["#{type.fetch("name")}::#{selector.fetch("name")}", selector.fetch("override")] }
    end
    assert_equal [["Microsoft.Xna.Framework.Graphics.GraphicsDevice::Viewport", { "set" => false }]], overrides

    strict = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)
    assert_equal 1, strict.fetch("PROPERTY_MAPPING_MISMATCH")
    assert_equal ["Microsoft.Xna.Framework.Graphics.GraphicsDevice::Viewport"],
                 strict.fetch("details").fetch("PROPERTY_MAPPING_MISMATCH")
  end

  # A guard nobody has seen fail is not evidence: dropping one selected type must be caught, and so
  # must dropping one member of a partially selected one.
  def test_the_guard_fails_on_a_planted_omission
    without_type = { "schemaVersion" => 1, "types" => SELECTION.fetch("types")[0..-2] }
    refute_equal CHECKED_IN, Builder.serialize(Builder.build(selection: without_type))

    trimmed = SELECTION.fetch("types").map do |type|
      type["include"] ? type.merge("include" => type.fetch("include")[0..-2]) : type
    end
    refute_equal CHECKED_IN, Builder.serialize(Builder.build(selection: { "schemaVersion" => 1, "types" => trimmed }))

    # And a type silently downgraded from "all of it" to an empty explicit list, which is the exact
    # shape the real drift had: a selection that says less than the file it is supposed to produce.
    downgraded = SELECTION.fetch("types").map do |type|
      type["complete"] ? { "name" => type.fetch("name"), "include" => [] } : type
    end
    built = Builder.build(selection: { "schemaVersion" => 1, "types" => downgraded })
    refute_equal CHECKED_IN, Builder.serialize(built)
    survivors = built.fetch("types").sum { |type| type.fetch("members").length }
    assert_operator survivors, :<, 2152, "the downgrade must lose members, not keep them"
    assert_equal survivors, SELECTION.fetch("types").sum { |type| type.fetch("include", []).length },
                 "exactly the explicitly selected members survive"

    # A selector that matches nothing is refused rather than silently dropping a member.
    assert_raises(RuntimeError) do
      Builder.build(selection: { "schemaVersion" => 1,
                                 "types" => [{ "name" => "Microsoft.Xna.Framework.Color",
                                               "include" => [{ "name" => "NoSuchMember" }] }] })
    end
  end
end
