# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# Foundation 51 — `Media.VisualizationData`.
#
# It sat on the frontier under `RUNTIME_DATA`, justified as "filled by
# MediaPlayer.GetVisualizationData from live playback". That is a statement about the **filler**, not
# the type: the constructor is public, seventy-five bytes, allocates everything it needs and reaches
# nothing. Foundation 24 settled the same case for `AudioListener` and `AudioEmitter`.
class VisualizationDataTest < Minitest::Test
  F = Microsoft::Xna::Framework
  V = Microsoft::Xna::Framework::Media::VisualizationData
  ROOT = Pathname(__dir__).join("..").expand_path
  CLR = "Microsoft.Xna.Framework.Media.VisualizationData"

  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FRONTIER = JSON.parse(
    ROOT.join("docs", "generated", "public-signature-dependency-report.json").read
  ).freeze

  # ------------------------------------------------------------------------- the pinned contract

  def test_it_is_three_identities_over_object
    type = REFERENCE.fetch(CLR)
    assert_equal "class", type.fetch("kind")
    assert_equal "System.Object", type.fetch("baseType")
    members = type.fetch("members")
    assert_equal 3, members.length
    constructor = members.find { |member| member.fetch("kind") == "constructor" }
    refute_nil constructor
    assert_equal "public", constructor.fetch("access")
    assert_empty constructor.fetch("parameters")
    properties = members.select { |member| member.fetch("kind") == "property" }
    assert_equal %w[Frequencies Samples].sort, properties.map { |m| m.fetch("name") }.sort
    properties.each do |property|
      assert_equal "System.Collections.ObjectModel.ReadOnlyCollection`1[System.Single]",
                   property.fetch("type")
      assert_equal true, property.fetch("get")
      assert_equal false, property.fetch("set")
    end
  end

  def test_it_is_complete_and_left_the_runtime_data_register
    assert_includes STRICT.fetch("completeTypeNames"), CLR
    refute_includes FRONTIER.fetch("runtimeDataRegister").keys, CLR
    refute(FRONTIER.fetch("dependencyCompleteCandidates").any? { |c| c.fetch("name") == CLR })
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
  end

  # ------------------------------------------------------------------------------- the constructor

  # `new float[0x100]` twice, then a ReadOnlyCollection over each. Every element is the CLR Single
  # default.
  def test_both_collections_are_two_hundred_and_fifty_six_zeroes
    data = V.new
    [data.Frequencies, data.Samples].each do |collection|
      assert_equal 256, collection.Count
      assert_equal 256, collection.to_a.length
      assert(collection.to_a.all? { |value| value.zero? }, "every element is the Single default")
      assert_equal 0.0, collection[0]
      assert_equal 0.0, collection[255]
    end
  end

  # Two `ldfld` getters: the same wrapper for the life of the object, and two distinct wrappers.
  def test_each_property_answers_the_same_wrapper
    data = V.new
    assert_same data.Frequencies, data.Frequencies
    assert_same data.Samples, data.Samples
    refute_same data.Frequencies, data.Samples
    refute_same V.new.Frequencies, data.Frequencies
  end

  # The CLR constructor stores the array *reference* in the wrapper, so the collection is a live
  # view rather than a snapshot — which is exactly what would let a filler's writes show through.
  def test_the_collections_are_live_views_over_the_backing_arrays
    data = V.new
    backing = data.instance_variable_get(:@frequencies)
    backing[3] = CNA::Runtime::Numeric.f32(0.5)
    assert_equal 0.5, data.Frequencies[3]
    assert_equal 256, data.Frequencies.Count
    # And the samples wrapper is over the other array, unaffected.
    assert_equal 0.0, data.Samples[3]
  end

  # `ReadOnlyCollection<T>` refuses mutation by having no mutating member at all, and the CLR type
  # argument survives as class metadata the verifier measures.
  def test_the_wrapper_is_the_projected_read_only_collection
    data = V.new
    assert_kind_of CNA::Runtime::ReadOnlyCollection, data.Frequencies
    assert_equal ["System.Single"], V::FloatCollection.clr_element_types
    %i[[]= Add Insert Remove Clear push <<].each do |absent|
      refute data.Frequencies.respond_to?(absent), absent
    end
    assert_equal 0, STRICT.fetch("GENERIC_MAPPING_MISMATCH")
  end

  # ------------------------------------------------------------------------------- no runtime

  # Completing it implies no filler, which is the whole of what the deferral was about.
  def test_it_implies_no_media_runtime_and_nothing_fills_it
    # Video arrived in Foundation 52 from its own IL; it is not a filler either.
    # `VideoPlayer` left this list when its blocker was audited; it is not a filler for this type
    # either, and what this milestone claimed is unchanged.
    %i[MediaPlayer MediaLibrary Song Album Playlist]
      .each { |absent| refute F::Media.const_defined?(absent, false), "Media::#{absent}" }
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    # `media` left this check when MediaSource bound the four routes that measure what CNA answers
    # for the one source XNA builds from a resource string; `visualization` stays, because nothing
    # is bound for the filler this type was deferred over.
    refute(symbols.any? { |symbol| symbol.include?("visualization") })
    refute(symbols.any? { |symbol| symbol.include?("media_player") || symbol.include?("media_library") })
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
  end
end
