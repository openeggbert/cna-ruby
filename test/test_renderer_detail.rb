# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"

# Foundation 50 — `Audio.RendererDetail`.
#
# It sat on the frontier under `RUNTIME_DATA`, justified as "values come from XACT audio renderer
# enumeration; no audio engine exists in this binding and no renderer has been enumerated". That is a
# statement about the **producer**, not the type: the pinned Xact.dll shows a sealed value type over
# two string fields whose seven identities are field reads, ordinal string comparisons and an XOR,
# with not one native reach among them. Foundation 25 settled the same case for `Graphics.DisplayMode`.
class RendererDetailTest < Minitest::Test
  F = Microsoft::Xna::Framework
  R = Microsoft::Xna::Framework::Audio::RendererDetail
  ROOT = Pathname(__dir__).join("..").expand_path
  CLR = "Microsoft.Xna.Framework.Audio.RendererDetail"

  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FRONTIER = JSON.parse(
    ROOT.join("docs", "generated", "public-signature-dependency-report.json").read
  ).freeze

  def build(name, id) = R.__send__(:new, name, id)

  # ------------------------------------------------------------------------- the pinned contract

  def test_it_is_a_sealed_value_type_with_seven_identities
    type = REFERENCE.fetch(CLR)
    assert_equal "struct", type.fetch("kind")
    assert_equal "System.ValueType", type.fetch("baseType")
    assert_equal true, type.fetch("sealed")
    assert_empty type.fetch("interfaces")
    members = type.fetch("members")
    assert_equal 7, members.length
    assert_equal %w[Equals GetHashCode ToString op_Equality op_Inequality].sort,
                 members.select { |m| m.fetch("kind") == "method" }.map { |m| m.fetch("name") }.sort
    assert_equal %w[FriendlyName RendererId].sort,
                 members.select { |m| m.fetch("kind") == "property" }.map { |m| m.fetch("name") }.sort
    # No constructor is a selected identity: the CLR one is `assembly`.
    refute(members.any? { |m| m.fetch("kind") == "constructor" })
  end

  def test_it_is_complete_and_left_the_runtime_data_register
    assert_includes STRICT.fetch("completeTypeNames"), CLR
    refute_includes STRICT.fetch("missingTypeNames"), CLR
    refute_includes FRONTIER.fetch("runtimeDataRegister").keys, CLR
    refute(FRONTIER.fetch("dependencyCompleteCandidates").any? { |c| c.fetch("name") == CLR })
    assert_equal 141, STRICT.fetch("COMPLETE_TYPES")
  end

  # Construction is private because the CLR constructor is `assembly` — the Foundation 25 rule.
  def test_construction_is_private
    assert_raises(NoMethodError) { R.new("a", "b") }
    refute_nil build("a", "b")
  end

  # ------------------------------------------------------------------------------- the members

  # Two `ldfld` getters over the two fields the internal constructor stores without validation.
  def test_the_two_properties_answer_the_stored_strings
    detail = build("Speakers", "id-1")
    assert_equal "Speakers", detail.FriendlyName
    assert_equal "id-1", detail.RendererId
    assert detail.FriendlyName.frozen?
    refute R.method_defined?(:FriendlyName=)
    refute R.method_defined?(:RendererId=)
  end

  # `op_Equality` compares both fields with `String::op_Equality`, ordinal, short-circuiting on the
  # name. `op_Inequality` is its negation. `Equals(object)` answers false for null and for a
  # different type first.
  def test_equality_is_both_fields_compared_ordinally
    left = build("Speakers", "id-1")
    same = build("Speakers", "id-1")
    other_name = build("Headset", "id-1")
    other_id = build("Speakers", "id-2")

    assert_equal left, same
    refute_equal left, other_name
    refute_equal left, other_id
    assert left != other_name
    assert left.Equals(same)
    refute left.Equals(other_id)
    refute left.Equals(nil)
    refute left.Equals("Speakers")
    # Ordinal, so case matters.
    refute_equal left, build("speakers", "id-1")
  end

  # `(IsNullOrEmpty(_name) ? 0 : _name.GetHashCode()) ^ (IsNullOrEmpty(_id) ? 0 : _id.GetHashCode())`.
  # The empty-or-null-contributes-zero rule and the XOR are exact; `System.String.GetHashCode` is a
  # Microsoft-internal algorithm this binding does not reproduce, and a CLR hash code is documented
  # as implementation-specific.
  def test_the_hash_shape_is_exact_even_though_the_clr_integer_is_not
    assert_equal build("a", "b").GetHashCode, build("a", "b").GetHashCode
    assert_equal 0, build("", "").GetHashCode, "both components empty contribute nothing"
    assert_equal 0, build(nil, nil).GetHashCode, "both components nil contribute nothing"
    # One empty component leaves the other's contribution alone, which is what XOR with zero does.
    assert_equal build("a", "").GetHashCode, build("a", nil).GetHashCode
    assert_equal build("", "b").GetHashCode, build(nil, "b").GetHashCode
    # Equal values hash equally, which is the whole of the observable contract.
    assert_equal build("x", "y").hash, build("x", "y").hash
  end

  # `ToString()` is declared and its whole body is `ValueType::ToString()`, which answers the type's
  # own fully-qualified CLR name — a deterministic string belonging to this type, not a localized
  # Microsoft resource.
  def test_to_string_is_the_clr_type_name
    assert_equal CLR, build("Speakers", "id-1").ToString
    assert_equal CLR, build(nil, nil).ToString
    assert_equal build("a", "b").ToString, build("a", "b").to_s
  end

  # A CLR value type copies on assignment, and the copy goes through the same private constructor.
  def test_it_copies_as_a_value
    original = build("Speakers", "id-1")
    copy = original.dup
    assert_equal original, copy
    refute_same original, copy
    assert original.frozen?
  end

  # ------------------------------------------------------------------------------- no runtime

  # Completing the type implies no enumerator that would fill it — the same statement Foundation 25
  # made for DisplayMode, and the one Native frontier 4 measured for the audio backend.
  def test_it_implies_no_audio_engine_and_nothing_produces_one
    %i[AudioEngine SoundBank WaveBank Cue SoundEffect SoundEffectInstance Microphone]
      .each { |absent| refute F::Audio.const_defined?(absent, false), "Audio::#{absent}" }
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    refute(symbols.any? { |symbol| symbol.include?("renderer") || symbol.include?("audio_engine") })
    refute(symbols.any? { |symbol| symbol.include?("sound_effect") })
    assert_equal 68, CNA::Native::Manifest::FUNCTIONS.length
  end
end
