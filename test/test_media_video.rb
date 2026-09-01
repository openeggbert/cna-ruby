# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# Foundation 52 — `Media.Video`.
#
# Its deferral was `RUNTIME_DATA`: "its internal constructor takes a GraphicsDevice, one of the
# deferred partial runtime types, and builds a Duration from tick components the content pipeline
# supplies; no producer exists". Both halves are about the **producer**. Naming a partial type in a
# signature is not a blocker — Foundation 40 established that a type is blocked only when its own IL
# *calls a member* of one — and "the content pipeline supplies the components" says who calls the
# constructor, not what the type does.
class MediaVideoTest < Minitest::Test
  F = Microsoft::Xna::Framework
  M = Microsoft::Xna::Framework::Media
  ROOT = Pathname(__dir__).join("..").expand_path
  CLR = "Microsoft.Xna.Framework.Media.Video"

  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FRONTIER = JSON.parse(
    ROOT.join("docs", "generated", "public-signature-dependency-report.json").read
  ).freeze

  def build(duration: 2500, width: 1920, height: 1080, fps: 29.97,
            soundtrack: M::VideoSoundtrackType::Music, device: nil, file: "clip.wmv")
    M::Video.__send__(:new, device, file, duration, width, height, fps, soundtrack)
  end

  # ------------------------------------------------------------------------- the pinned contract

  def test_it_is_five_get_only_properties_and_no_selected_constructor
    type = REFERENCE.fetch(CLR)
    assert_equal "class", type.fetch("kind")
    assert_equal "System.Object", type.fetch("baseType")
    assert_equal true, type.fetch("sealed")
    members = type.fetch("members")
    assert_equal 5, members.length
    assert(members.all? { |member| member.fetch("kind") == "property" })
    assert(members.all? { |member| member.fetch("get") && !member.fetch("set") })
    assert_equal({ "Duration" => "System.TimeSpan", "Width" => "System.Int32",
                   "Height" => "System.Int32", "FramesPerSecond" => "System.Single",
                   "VideoSoundtrackType" => "Microsoft.Xna.Framework.Media.VideoSoundtrackType" },
                 members.to_h { |m| [m.fetch("name"), m.fetch("type")] })
    # The two `assembly` getters, GraphicsDevice and Filename, are not identities.
    refute(members.any? { |m| %w[GraphicsDevice Filename].include?(m.fetch("name")) })
  end

  def test_it_is_complete_and_left_the_runtime_data_register
    assert_includes STRICT.fetch("completeTypeNames"), CLR
    refute_includes FRONTIER.fetch("runtimeDataRegister").keys, CLR
    refute(FRONTIER.fetch("dependencyCompleteCandidates").any? { |c| c.fetch("name") == CLR })
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
  end

  def test_construction_is_private
    assert_raises(NoMethodError) { M::Video.new(nil, "x", 0, 0, 0, 0.0, M::VideoSoundtrackType::Music) }
    refute_nil build
  end

  # ------------------------------------------------------------------------------- the members

  # The five properties are one `ldfld` each over what the constructor stored without validation.
  def test_the_five_properties_answer_what_the_constructor_stored
    video = build(width: 1280, height: 720, soundtrack: M::VideoSoundtrackType::Dialog)
    assert_equal 1280, video.Width
    assert_equal 720, video.Height
    assert_equal M::VideoSoundtrackType::Dialog, video.VideoSoundtrackType
    assert video.frozen?
    %i[Duration= Width= Height= FramesPerSecond= VideoSoundtrackType=].each do |writer|
      refute M::Video.method_defined?(writer), writer
    end
  end

  # `duration` arrives as an Int32 and the field is `new TimeSpan(0, 0, 0, 0, duration)` — the
  # five-argument form, whose last parameter is **milliseconds**. TimeSpan projects to Float seconds.
  def test_the_duration_argument_is_milliseconds
    assert_in_delta 2.5, build(duration: 2500).Duration, 1e-9
    assert_in_delta 0.0, build(duration: 0).Duration, 1e-9
    assert_in_delta 0.001, build(duration: 1).Duration, 1e-9
    assert_in_delta 60.0, build(duration: 60_000).Duration, 1e-9
  end

  # `framesPerSecond` is a `float32` field, so the projection rounds to binary32 as every Single in
  # this binding does.
  def test_frames_per_second_is_a_single
    assert_equal CNA::Runtime::Numeric.f32(29.97), build(fps: 29.97).FramesPerSecond
    refute_equal 29.97, build(fps: 29.97).FramesPerSecond
  end

  # The internal constructor stores the GraphicsDevice and calls no member of it, which is exactly
  # why naming a partial type here was never a blocker.
  def test_the_graphics_device_is_stored_and_never_reached
    video = build(device: nil)
    assert_nil video.instance_variable_get(:@graphics_device)
    # It is `assembly` in the CLR, so no reader is projected for it.
    refute M::Video.method_defined?(:GraphicsDevice)
    refute M::Video.method_defined?(:Filename)
  end

  # ------------------------------------------------------------------------------- no runtime

  def test_it_implies_no_media_runtime_and_nothing_produces_one
    %i[MediaPlayer MediaLibrary Song Album Playlist VideoPlayer]
      .each { |absent| refute M.const_defined?(absent, false), "Media::#{absent}" }
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    # `media_` left this check when MediaSource bound the four routes that measure what CNA answers
    # for the source XNA builds from a resource string. `video` stays: no route is bound for it.
    refute(symbols.any? { |symbol| symbol.include?("video") })
    refute(symbols.any? { |symbol| symbol.include?("media_player") || symbol.include?("media_library") })
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
  end
end
