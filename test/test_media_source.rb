# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `Media.MediaSource` — the last entry of the frontier's `RUNTIME_DATA` register, and the plainest
# wrong one of the seven producer-shaped deferrals.
#
# The reasoning was "GetAvailableMediaSources enumerates the host media sources; no media stack has
# been queried". The method enumerates nothing: it is one `newarr`, one `newobj` and a `stelem.ref`
# over an object built from `MediaSourceType.LocalDevice` and a resource string. XNA queries no
# media stack either.
class MediaSourceTest < Minitest::Test
  F = Microsoft::Xna::Framework
  M = Microsoft::Xna::Framework::Media
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Media.MediaSource"

  # ------------------------------------------------------------------- the contract, from metadata

  def test_the_whole_contract_is_four_identities_and_no_constructor
    contract = REFERENCE.fetch(NAME)
    assert contract.fetch("sealed")
    assert_equal 4, contract.fetch("members").length
    assert_empty contract.fetch("members").select { |m| m.fetch("kind") == "constructor" },
                 "the constructor is private, so a consumer reaches one only through the static"
    assert_raises(NoMethodError) { M::MediaSource.new }
    assert_equal %i[MediaSourceType Name ToString to_s].sort,
                 M::MediaSource.public_instance_methods(false).sort
    %i[Name= MediaSourceType=].each { |absent| refute M::MediaSource.public_method_defined?(absent) }
  end

  # The register is empty now. Every entry it ever held described a producer rather than the type.
  def test_the_runtime_data_register_is_empty_and_the_type_is_complete
    assert_empty FRONTIER.fetch("runtimeDataRegister")
    assert_includes STRICT.fetch("completeTypeNames"), NAME
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    refute_includes FRONTIER.fetch("dependencyCompleteCandidates").map { |c| c.fetch("name") }, NAME
    refute(FRONTIER.fetch("blockerSummary").keys.any? { |key| key.include?("RUNTIME_DATA") })
  end

  # `IList`1` is named once in the whole selected surface, here, and the IL returns a plain array.
  def test_the_ilist_projection_is_registered_and_is_what_the_il_returns
    assert_equal "Array", CNA::Runtime::BclProjection::TYPES.fetch("System.Collections.Generic.IList`1")
    assert_equal ReviewedScoreboard::BCL_PROJECTED_IDENTITIES, STRICT.fetch("BCL_PROJECTED_IDENTITIES")
    member = REFERENCE.fetch(NAME).fetch("members").find { |m| m.fetch("name") == "GetAvailableMediaSources" }
    assert member.fetch("static")
    assert_equal "System.Collections.Generic.IList`1[#{NAME}]", member.fetch("returnType")
  end

  # ------------------------------------------------------------------------------ live behaviour

  # `ldc.i4.1; newarr; newobj; stelem.ref; ret` — one array, one element, freshly built every call.
  def test_it_answers_one_fresh_local_device_every_call
    first = M::MediaSource.GetAvailableMediaSources
    second = M::MediaSource.GetAvailableMediaSources

    assert_instance_of Array, first
    assert_equal 1, first.length
    refute first.equal?(second), "newarr builds a new array each call"
    refute first[0].equal?(second[0]), "and newobj a new element"

    source = first[0]
    assert_instance_of M::MediaSource, source
    assert_equal M::MediaSourceType::LocalDevice, source.MediaSourceType
    assert_equal 0, source.MediaSourceType.to_i
  end

  # `name = FrameworkResources.WmpMediaSource`, and `ToString` is `get_Name()` — the property,
  # not the field. The value was extracted from the pinned assembly's own resource table.
  def test_the_name_is_the_pinned_resource_string_and_to_string_is_the_property
    source = M::MediaSource.GetAvailableMediaSources.first
    assert_equal "Local Windows Media Player library", source.Name
    assert_equal M::MediaSource::WMP_MEDIA_SOURCE, source.Name
    assert_equal source.Name, source.ToString
    assert_equal source.Name, source.to_s
  end

  # It needs no Game at all, which is what makes it different from every other type this session
  # built: the IL reaches nothing, so neither does the projection.
  def test_it_needs_no_game_and_reaches_nothing_native
    assert_nil CNA::Runtime::Context.instance_variable_get(:@current)
    source = M::MediaSource.GetAvailableMediaSources.first
    assert_equal "Local Windows Media Player library", source.Name
    il = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read)
    refute il.fetch("types").fetch(NAME).fetch("nativeReachable"),
           "the IL reaches no native entry point, which is why no Game is needed"
  end

  # ------------------------------------------------------------------------- and what CNA answers

  class HostGame < F::Game
    attr_reader :result

    def initialize(&body)
      @body = body
      @result = nil
      super()
    end

    def Update(_gameTime)
      @result = @body.call
    ensure
      self.Exit
    end
  end

  # DEVIATION, recorded: XNA's name is a **localized** resource string, so its value depends on the
  # UI culture; the qualified profile is the en-US assembly. CNA answers a different string for the
  # same source, and the divergence is measured here rather than only described.
  def test_cna_answers_the_same_source_under_a_different_name
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = HostGame.new do
      source = M::MediaSource.GetAvailableMediaSources.first
      [source.__send__(:native_sources), source.Name, source.MediaSourceType]
    end
    begin
      game.Run
      native, name, type = game.result
    ensure
      game.Dispose
    end

    assert_equal 1, native.length, "CNA reports one source too"
    assert_equal type, native[0][0], "and agrees it is a LocalDevice"
    refute_empty native[0][1]
    refute_equal name, native[0][1],
                 "but names it differently, which is the deviation this test exists to hold"
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_produces_no_media_library_player_or_song
    # `VideoPlayer` left this list when its NATIVE_RUNTIME was audited and found not to be a
    # blocker; what **this** milestone claimed is unchanged, and the MediaPlayer/MediaLibrary half
    # of the namespace is still absent whole.
    %i[MediaLibrary MediaPlayer Song Album Artist Playlist Picture MediaQueue]
      .each { |absent| refute M.const_defined?(absent, false), "Media::#{absent}" }
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    refute(symbols.any? { |s| s.start_with?("cna_media_player_", "cna_media_library_", "cna_song_") })
    assert_equal 4, symbols.count { |s| s.start_with?("cna_media_source_") }
  end
end
