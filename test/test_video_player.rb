# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `Media.VideoPlayer` — the last unaudited candidate on the dependency frontier, and the eleventh
# time `NATIVE_RUNTIME` turned out not to be a blocker. The routes exist, execute and behave; the
# optional video decoder really is compiled into the qualified artifact. What is genuinely missing is
# a `Video` **producer**, and that is `Media.Video`'s deferral rather than this type's.
class VideoPlayerTest < Minitest::Test
  F = Microsoft::Xna::Framework
  M = Microsoft::Xna::Framework::Media
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  IL = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read).freeze
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Media.VideoPlayer"

  # --------------------------------------------------------------- the audit, before the work

  # Fifteen native-reachable members, which is why this was the candidate most likely to be blocked
  # for the reason its blocker column reported. It was measured instead.
  def test_the_blocker_named_fifteen_members_and_every_one_has_a_route
    entry = IL.fetch("types").fetch(NAME)
    assert entry.fetch("nativeReachable")
    assert_equal 15, entry.fetch("nativeReachableMethods").length
    assert_includes entry.fetch("nativeReachableMethods"), ".ctor"
    assert_includes entry.fetch("nativeReachableMethods"), "GetTexture"
    assert_equal "Microsoft.Xna.Framework.Video.dll", entry.fetch("assembly")
    assert_equal "17538b1ca9d48a993e2cd88c96b436df08e7abb4aec5d4758eb21feb580d6e06",
                 entry.fetch("assemblySha256")

    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    %w[create dispose destroy play pause resume stop get_texture get_video get_state
       get_is_disposed get_is_looped set_is_looped get_is_muted set_is_muted
       get_play_position_ticks get_volume set_volume].each do |suffix|
      assert_includes symbols, "cna_video_player_#{suffix}"
    end
    # Three CNA extensions with no XNA identity stay unbound.
    %w[cna_video_player_set_audio_track_ext cna_video_player_set_video_track_ext
       cna_video_player_get_frame_ext cna_video_player_copy_type_name].each do |absent|
      refute_includes symbols, absent
    end
  end

  def test_it_is_complete_and_the_frontier_is_at_rest
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_equal ReviewedScoreboard::TARGET_MEMBERS, STRICT.fetch("TARGET_MEMBERS")
    assert_includes STRICT.fetch("completeTypeNames"), NAME
    assert_equal 0, STRICT.fetch("localDiagnostics").fetch(NAME)
    # Three candidates when this milestone landed; the Effect cluster then built EffectAnnotation
    # and uncovered EffectMaterial and DirectionalLight behind the Effect base, which is a frontier
    # advancing rather than regressing. What this test claims -- that VideoPlayer left it -- stands.
    candidates = FRONTIER.fetch("dependencyCompleteCandidates").map { |c| c.fetch("name") }.sort
    assert_equal %w[Microsoft.Xna.Framework.Design.MathTypeConverter
                    Microsoft.Xna.Framework.Graphics.GraphicsAdapter], candidates
    refute_includes candidates, NAME
    assert_empty FRONTIER.fetch("consumableCandidates")
    # Every Media type this project ever selected is complete now, and so is every one it did not:
    # the MediaPlayer/MediaLibrary half, unselected and missing whole when this milestone ran, was
    # selected and built at Foundation 103, and `Song` -- recorded partial there on three routes
    # said not to exist -- completed at Foundation 104 when they turned out to.
    assert_equal %w[Microsoft.Xna.Framework.Media.Album
                    Microsoft.Xna.Framework.Media.AlbumCollection
                    Microsoft.Xna.Framework.Media.Artist
                    Microsoft.Xna.Framework.Media.ArtistCollection
                    Microsoft.Xna.Framework.Media.Genre
                    Microsoft.Xna.Framework.Media.GenreCollection
                    Microsoft.Xna.Framework.Media.MediaLibrary
                    Microsoft.Xna.Framework.Media.MediaPlayer
                    Microsoft.Xna.Framework.Media.MediaQueue
                    Microsoft.Xna.Framework.Media.MediaSource
                    Microsoft.Xna.Framework.Media.MediaSourceType
                    Microsoft.Xna.Framework.Media.MediaState
                    Microsoft.Xna.Framework.Media.Picture
                    Microsoft.Xna.Framework.Media.PictureAlbum
                    Microsoft.Xna.Framework.Media.PictureAlbumCollection
                    Microsoft.Xna.Framework.Media.PictureCollection
                    Microsoft.Xna.Framework.Media.Playlist
                    Microsoft.Xna.Framework.Media.PlaylistCollection
                    Microsoft.Xna.Framework.Media.Song
                    Microsoft.Xna.Framework.Media.SongCollection
                    Microsoft.Xna.Framework.Media.Video
                    Microsoft.Xna.Framework.Media.VideoPlayer
                    Microsoft.Xna.Framework.Media.VideoSoundtrackType
                    Microsoft.Xna.Framework.Media.VisualizationData],
                 STRICT.fetch("completeTypeNames").grep(/\AMicrosoft\.Xna\.Framework\.Media\./).sort
    assert_empty STRICT.fetch("partialTypes").keys.grep(/\AMicrosoft\.Xna\.Framework\.Media\./)
  end

  def test_the_contract_is_fifteen_members_over_idisposable
    contract = REFERENCE.fetch(NAME)
    assert contract.fetch("sealed")
    assert_equal ["System.IDisposable"], contract.fetch("interfaces")
    assert_equal 15, contract.fetch("members").length
    # `IsDisposed` comes from the NativeResource mixin every owned handle in this binding uses, so
    # it is not declared directly here -- but it is public and it is the contract's.
    assert M::VideoPlayer.public_method_defined?(:IsDisposed)
    assert_equal %i[Dispose Finalize GetTexture IsLooped IsLooped= IsMuted IsMuted=
                    Pause Play PlayPosition Resume State Stop Video Volume Volume=].sort,
                 M::VideoPlayer.public_instance_methods(false).sort
  end

  # ------------------------------------------------------------------------------ live behaviour

  class PlayerGame < F::Game
    attr_reader :result

    def initialize(&body)
      @body = body
      @result = nil
      super()
      F::GraphicsDeviceManager.new(self)
    end

    def LoadContent
      @result = @body.call
    ensure
      self.Exit
    end
  end

  def with_player
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = PlayerGame.new { yield M::VideoPlayer.new }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  # The IL's own constructor defaults: looping false, muted false, volume 1f, position zero, and a
  # decoder created straight away. The state a fresh decoder reports is Stopped.
  def test_the_constructor_defaults_are_the_ils_own
    values = with_player do |player|
      [player.IsDisposed, player.IsLooped, player.IsMuted, player.Volume,
       player.PlayPosition, player.State, player.Video]
    end
    assert_equal [false, false, false, 1.0, 0.0, M::MediaState::Stopped, nil], values
    assert_equal M::VideoPlayer::DEFAULT_VOLUME, 1.0
  end

  # Every setter round-trips through the decoder, and the getters are the cached fields the IL reads
  # with a bare `ldfld`.
  def test_every_setter_round_trips
    values = with_player do |player|
      player.IsLooped = true
      player.IsMuted = true
      player.Volume = 0.25
      [player.IsLooped, player.IsMuted, player.Volume,
       (begin; player.IsLooped = 1; nil; rescue => e; e.class; end),
       (begin; player.Volume = "1"; nil; rescue => e; e.class; end)]
    end
    assert_equal [true, true, 0.25, TypeError, TypeError], values
  end

  # `if (value < 0f || !(value <= 1f)) throw new ArgumentOutOfRangeException("value")`. The second
  # half is `ble.un` -- **unordered** -- so NaN takes the accepting branch, which is the same
  # asymmetry `AudioCategory.SetVolume` records and the opposite of `SoundEffectInstance.Volume`.
  def test_the_volume_range_is_the_ils_unordered_comparison
    values = with_player do |player|
      [(begin; player.Volume = -0.001; nil; rescue => e; e.class; end),
       (begin; player.Volume = 1.001; nil; rescue => e; e.class; end),
       (begin; player.Volume = 0.0; :ok; rescue => e; e.class; end),
       (begin; player.Volume = 1.0; :ok; rescue => e; e.class; end),
       (begin; player.Volume = Float::NAN; :accepted; rescue => e; e.class; end)]
    end
    assert_equal [RangeError, RangeError, :ok, :ok], values[0, 4]
    assert_includes [:accepted, CNA::NativeError], values[4],
                    "NaN passes the managed check; what refuses it, if anything, is CNA"
  end

  # The transport controls are no-ops with no active video -- `if (!IsValidDecoder || activeVideo ==
  # null) return;` -- and they really are reached rather than skipped, because a disposed player
  # raises instead.
  def test_the_transport_controls_are_no_ops_without_a_video
    values = with_player do |player|
      player.Pause
      player.Resume
      player.Stop
      state = player.State
      player.Dispose
      [state,
       (begin; player.Pause; nil; rescue => e; e.class; end),
       (begin; player.Stop; nil; rescue => e; e.class; end),
       (begin; player.State; nil; rescue => e; e.class; end)]
    end
    assert_equal M::MediaState::Stopped, values[0]
    assert_equal [CNA::DisposedObjectError] * 3, values[1..]
  end

  # `GetTexture` is the one member that throws rather than returning when nothing is playing, and
  # the IL constructs a **bare** `InvalidOperationException` with no message at all.
  def test_get_texture_throws_when_nothing_is_playing
    values = with_player do |player|
      begin
        player.GetTexture
        nil
      rescue => error
        error.class
      end
    end
    assert_equal RuntimeError, values
    assert_equal "RuntimeError",
                 CNA::Runtime::BclProjection::THROWN_EXCEPTIONS.fetch("System.InvalidOperationException")
  end

  # The measured gap, stated as a test rather than only as prose: `Play` validates exactly as XNA
  # does and then cannot forward, because nothing in this binding produces a `Video`.
  def test_play_validates_like_xna_and_then_has_no_argument_to_be_given
    values = with_player do |player|
      [(begin; player.Play(nil); nil; rescue => e; e.class; end),
       (begin; player.Play("video"); nil; rescue => e; e.class; end)]
    end
    assert_equal [ArgumentError, TypeError], values

    # And the reason is measurable rather than asserted: Video's constructor is private, no route
    # in this manifest produces one, and CNA exports no content route for video either.
    assert_raises(NoMethodError) { M::Video.new(nil, nil, 0, 0, 0, 0, 0) }
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    refute_includes symbols, "cna_content_manager_load_video"
    refute symbols.any? { |symbol| symbol.start_with?("cna_video_create") }
    assert_includes M::VideoPlayer::NO_VIDEO_PRODUCER, "ContentManager.Load<Video>"
  end

  # `Dispose` is idempotent and the three field getters answer **after** it, because the IL reads
  # them with a bare `ldfld` outside the lock and without `ThrowIfDisposed`. The setters do not.
  def test_disposal_is_idempotent_and_the_field_getters_survive_it
    values = with_player do |player|
      player.Volume = 0.5
      player.IsLooped = true
      player.Dispose
      player.Dispose
      [player.IsDisposed, player.Volume, player.IsLooped, player.IsMuted,
       (begin; player.Volume = 0.25; nil; rescue => e; e.class; end),
       (begin; player.IsLooped = false; nil; rescue => e; e.class; end)]
    end
    assert_equal [true, 0.5, true, false, CNA::DisposedObjectError, CNA::DisposedObjectError], values
  end

  # `Finalize` is `Dispose(false)`, and no Ruby finalizer is registered: nothing in this binding is
  # released by the garbage collector.
  def test_finalize_disposes_and_no_ruby_finalizer_is_registered
    values = with_player do |player|
      player.__send__(:Finalize)
      player.IsDisposed
    end
    assert values
    source = ROOT.join("lib", "microsoft", "xna", "framework", "media.rb").read.lines
                 .reject { |line| line.strip.start_with?("#") }.join
    refute_includes source, "define_finalizer"
    refute_includes source, "ObjectSpace"
  end

  # ------------------------------------------------------------------- and exactly what it does not
  def test_it_adds_no_media_player_song_or_library_surface
    # Foundation 103 built all nine of these. What **this** milestone claimed is that its own
    # sixteen routes added none of them, which is still exactly true: every route it bound is a
    # `cna_video_player_*` one, and not one of them names a song, a library or a picture.
    %i[MediaPlayer MediaLibrary Song SongCollection AlbumCollection Album Artist Genre Picture]
      .each { |built| assert M.const_defined?(built, false), built.to_s }
    video_routes = CNA::Native::Manifest::FUNCTIONS.map(&:symbol).grep(/\Acna_video_player_/)
    refute_empty video_routes
    refute(video_routes.any? { |route| route.match?(/song|librar|picture|album|artist|genre/) })
    # No claim is made about anything visible: HEADLESS qualifies execution, not rendered output.
    refute M::VideoPlayer.public_method_defined?(:Draw)
  end
end
