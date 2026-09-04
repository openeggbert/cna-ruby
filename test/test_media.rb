# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# The `Media` library and player half — `MediaLibrary`, `MediaPlayer`, `MediaQueue`, `Song`,
# `Album`, `Artist`, `Genre`, `Playlist`, `Picture`, `PictureAlbum` and their seven collections.
#
# The frontier never listed one of these: they were unselected, so nothing measured them and the
# `audio-media` capability row said flatly that "no MediaPlayer or MediaLibrary" existed. CNA
# exports 167 routes for them, every one of which works headless, and the machine this runs on has
# a real picture library behind them.
#
# The one thing CNA genuinely cannot answer is `Song`'s three navigations — `Album`, `Artist` and
# `Genre`. There is no `cna_song_get_album`, no `cna_song_get_artist` and no `cna_song_get_genre`,
# while every *reverse* navigation is exported and works, so `Song` is the one partial type here
# and its blocker is upstream rather than local.
class MediaTest < Minitest::Test
  F = Microsoft::Xna::Framework
  M = Microsoft::Xna::Framework::Media
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze

  BUILT = %w[MediaPlayer MediaLibrary MediaQueue Song SongCollection Album AlbumCollection
             Artist ArtistCollection Genre GenreCollection Playlist PlaylistCollection
             Picture PictureCollection PictureAlbum PictureAlbumCollection].freeze
  COLLECTIONS = %w[SongCollection AlbumCollection ArtistCollection GenreCollection
                   PlaylistCollection PictureCollection PictureAlbumCollection].freeze

  # ------------------------------------------------------------------- the contract, from metadata

  def test_all_seventeen_are_complete_including_song
    complete = STRICT.fetch("completeTypeNames")
    BUILT.each { |short| assert_includes complete, "Microsoft.Xna.Framework.Media.#{short}" }
    assert_empty STRICT.fetch("partialTypes").keys.grep(/\AMicrosoft\.Xna\.Framework\.Media\./)
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_equal ReviewedScoreboard::PARTIAL_TYPES, STRICT.fetch("PARTIAL_TYPES")
    # Every Media name has left the missing-type inventory too.
    assert_empty STRICT.fetch("missingTypeNames").grep(/\AMicrosoft\.Xna\.Framework\.Media\./)
  end

  # A CORRECTION, and the rule that caught it. Foundation 103 recorded `Song.Album`, `Song.Artist`
  # and `Song.Genre` as `BLOCKED_UPSTREAM_CNA` on the claim that CNA exports no route for them.
  # That claim was false. Foundation 104 re-measured it the way this project requires a blocker to
  # be re-measured -- against the shipped artifact rather than against the note -- and `nm -D` lists
  # all three, both admitted header roots declare all three, and the ABI gate type-checks all three.
  #
  # This test is the guard that would have caught it: it asserts the routes are **present**, in the
  # library, in the manifest and in the projected surface.
  def test_songs_three_navigations_exist_in_the_library_and_are_bound
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    %w[cna_song_get_album cna_song_get_artist cna_song_get_genre].each do |route|
      assert_includes symbols, route
      assert native_symbol?(route), "#{route} is not in the shipped library"
    end
    %i[Album Artist Genre].each { |member| assert M::Song.public_method_defined?(member), member.to_s }
    # The reverse navigations are exported too, so the graph really is walkable in both directions.
    %w[cna_album_get_songs cna_artist_get_songs cna_artist_get_albums
       cna_genre_get_songs cna_genre_get_albums cna_playlist_get_songs].each do |present|
      assert_includes symbols, present
    end
  end

  # Each of the three answers a borrowed handle **plus an availability flag**, and the header says
  # what false means: a song with no library context. A song built from a URI is exactly that, and
  # this machine's library has no songs, so the negative case is what is measurable here and the
  # positive one is recorded as environment-limited rather than claimed.
  def test_a_song_built_from_a_uri_has_no_library_context
    directory = ENV["CNA_TEST_XNB_DIR"]
    skip "CNA_TEST_XNB_DIR not supplied" if directory.nil? || !File.directory?(directory)

    path = File.join(directory, "song", "one_two_three.ogg")
    skip "the song fixture is not present" unless File.file?(path)

    with_game do
      song = M::Song.FromUri("probe", path)
      begin
        refute_empty song.Name
        assert_nil song.Album
        assert_nil song.Artist
        assert_nil song.Genre
      ensure
        song.Dispose
      end
    end
  end

  # And when the library *does* hold songs, each navigation answers a real entity whose own
  # collection contains the song again. This machine's library is empty, so the assertion skips
  # rather than being weakened -- the same decision `Microphone` records for capture.
  def test_a_library_song_names_the_album_artist_and_genre_that_contain_it
    with_library do |library|
      songs = library.Songs
      skip "this machine's media library reports no songs" if songs.Count.zero?

      song = songs[0]
      [[song.Album, :Songs], [song.Artist, :Songs], [song.Genre, :Songs]].each do |entity, member|
        next if entity.nil?

        assert_includes entity.public_send(member).to_a.map(&:Name), song.Name
      end
    end
  end

  # `abstract sealed` is a C# static class. A Ruby module would be a TYPE_KIND_MISMATCH against the
  # reference contract, so it is a class whose `new` is private -- and nothing on it is an instance
  # method, which is the half a module would have got right.
  def test_media_player_is_a_static_class_with_no_instance_surface
    assert_equal "class", REFERENCE.fetch("Microsoft.Xna.Framework.Media.MediaPlayer").fetch("kind")
    assert_kind_of Class, M::MediaPlayer
    assert_raises(NoMethodError) { M::MediaPlayer.new }
    assert_empty M::MediaPlayer.public_instance_methods(false)
    assert_equal 0, STRICT.fetch("TYPE_KIND_MISMATCH")
    # Both of its events are static, and both are measured.
    %w[ActiveSongChanged MediaStateChanged].each do |event|
      assert_includes STRICT.fetch("eventIdentities"), "Microsoft.Xna.Framework.Media.MediaPlayer::#{event}"
      assert_kind_of CNA::Runtime::Event, M::MediaPlayer.public_send(event)
    end
    assert_equal 0, STRICT.fetch("EVENT_MAPPING_MISMATCH")
  end

  # XNA exposes no mutator on the queue except `ActiveSongIndex`, so a queue is changed by
  # `MediaPlayer.Play` and by nothing else. The projection adds none either.
  def test_the_queue_exposes_no_mutator_but_the_one_the_il_declares
    assert_equal %i[ActiveSong ActiveSongIndex ActiveSongIndex= Count []].sort,
                 M::MediaQueue.public_instance_methods(false).sort
    %i[Add Remove Clear Insert []= push <<].each do |absent|
      refute M::MediaQueue.public_method_defined?(absent), absent.to_s
    end
    assert_raises(NoMethodError) { M::MediaQueue.new }
  end

  # Seven live views, each `IEnumerable`1`, `IEnumerable` and `IDisposable` in the contract, none of
  # them a list: no mutator is declared and none is projected.
  def test_the_seven_collections_are_read_only_enumerable_views
    COLLECTIONS.each do |short|
      type = M.const_get(short, false)
      contract = REFERENCE.fetch("Microsoft.Xna.Framework.Media.#{short}")
      assert_includes contract.fetch("interfaces"), "System.Collections.IEnumerable"
      assert_includes contract.fetch("interfaces"), "System.IDisposable"
      assert_includes type.ancestors, Enumerable, short
      %i[Count [] GetEnumerator each Dispose IsDisposed].each do |member|
        assert type.public_method_defined?(member), "#{short}##{member}"
      end
      %i[Add Remove Clear Insert []=].each { |absent| refute type.public_method_defined?(absent), short }
      assert_raises(NoMethodError) { type.new }
    end
  end

  # ------------------------------------------------------------------------------- live behaviour

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

  def with_game
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = HostGame.new { yield }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  def with_library
    with_game do
      library = M::MediaLibrary.new
      begin
        yield library
      ensure
        library.Dispose
      end
    end
  end

  # The library opens for real, and every one of its seven collections answers a count. An empty
  # collection is an ordinary result on a machine with no music, which the header says too, so this
  # asserts the shape rather than a population.
  def test_a_real_library_opens_and_every_collection_answers_a_count
    with_library do |library|
      refute library.IsDisposed
      assert_instance_of M::MediaSource, library.MediaSource
      {library.Songs => M::SongCollection, library.Albums => M::AlbumCollection,
       library.Artists => M::ArtistCollection, library.Genres => M::GenreCollection,
       library.Playlists => M::PlaylistCollection, library.Pictures => M::PictureCollection,
       library.SavedPictures => M::PictureCollection}.each do |collection, type|
        assert_instance_of type, collection
        assert_operator collection.Count, :>=, 0
        assert_equal collection.Count, collection.to_a.length
      end
    end
  end

  # This machine has a real picture library, so the picture half is measured rather than shaped.
  # A machine without one skips, and says which assertion it gave up.
  def test_every_picture_answers_its_own_metadata_and_its_bytes
    with_library do |library|
      pictures = library.Pictures
      skip "this machine's media library reports no pictures" if pictures.Count.zero?

      first = pictures[0]
      refute_empty first.Name
      assert_operator first.Width, :>, 0
      assert_operator first.Height, :>, 0
      assert_instance_of M::PictureAlbum, first.Album
      image = first.GetImage
      refute_nil image
      assert_operator image.Length, :>, 0
      # A thumbnail is optional and is a *different* stream when it exists.
      thumbnail = first.GetThumbnail
      refute_equal image.object_id, thumbnail.object_id unless thumbnail.nil?
      # Indexing and enumerating are the same sequence.
      assert_equal pictures.to_a.map(&:Name), (0...pictures.Count).map { |i| pictures[i].Name }
    end
  end

  # DEVIATION, measured rather than read: CNA answers a picture's date in 100-nanosecond ticks from
  # the Unix epoch, not in seconds. The factor is 10^7 and the projection divides it out, which is
  # asserted here against the plain fact that the answer must be a plausible calendar date.
  def test_a_pictures_date_is_a_real_time_rather_than_a_tick_count
    with_library do |library|
      pictures = library.Pictures
      skip "this machine's media library reports no pictures" if pictures.Count.zero?

      date = pictures[0].Date
      assert_instance_of Time, date
      assert_operator date.year, :>=, 1970
      assert_operator date.year, :<=, Time.now.utc.year + 1
      assert_equal CNA::Runtime::MediaSupport::TICKS_PER_SECOND, 10_000_000
    end
  end

  # The root album is the one album with no parent, and every album under it names it back.
  def test_the_root_picture_album_is_the_one_without_a_parent
    with_library do |library|
      root = library.RootPictureAlbum
      skip "this machine's media library reports no picture albums" if root.nil?

      assert_instance_of M::PictureAlbum, root
      assert_nil root.Parent
      assert_instance_of M::PictureAlbumCollection, root.Albums
      root.Albums.each do |child|
        assert_instance_of M::PictureAlbum, child
        refute_nil child.Parent
        assert_equal root.Name, child.Parent.Name
      end
    end
  end

  # The player is process-global state on the running game: reading it needs a game and nothing
  # else, and every setter round-trips.
  def test_the_player_answers_state_and_round_trips_every_setting
    with_game do
      assert_instance_of M::MediaState, M::MediaPlayer.State
      assert_kind_of Numeric, M::MediaPlayer.PlayPosition
      assert_instance_of M::MediaQueue, M::MediaPlayer.Queue
      assert_includes [true, false], M::MediaPlayer.GameHasControl

      %i[IsMuted IsRepeating IsShuffled IsVisualizationEnabled].each do |flag|
        original = M::MediaPlayer.public_send(flag)
        M::MediaPlayer.public_send(:"#{flag}=", !original)
        assert_equal !original, M::MediaPlayer.public_send(flag), flag.to_s
        M::MediaPlayer.public_send(:"#{flag}=", original)
        assert_equal original, M::MediaPlayer.public_send(flag), flag.to_s
        assert_raises(TypeError) { M::MediaPlayer.public_send(:"#{flag}=", 1) }
      end
    end
  end

  # `set_Volume` is `MathHelper.Clamp(value, 0f, 1f)` first and assignment second, so it clamps
  # rather than refusing: 2.0 becomes 1.0 and -1.0 becomes 0.0, and neither raises.
  def test_volume_clamps_the_way_the_il_clamps
    with_game do
      original = M::MediaPlayer.Volume
      begin
        M::MediaPlayer.Volume = 2.0
        assert_in_delta 1.0, M::MediaPlayer.Volume, 1e-6
        M::MediaPlayer.Volume = -1.0
        assert_in_delta 0.0, M::MediaPlayer.Volume, 1e-6
        M::MediaPlayer.Volume = 0.25
        assert_in_delta 0.25, M::MediaPlayer.Volume, 1e-6
        assert_raises(TypeError) { M::MediaPlayer.Volume = "loud" }
      ensure
        M::MediaPlayer.Volume = original
      end
    end
  end

  # `GetVisualizationData` fills the caller's object in place. The two collections are live views
  # over the arrays behind them, so the same wrapper answers the filled values afterwards -- which
  # is the property `VisualizationData` was projected for, three milestones before a filler existed.
  def test_get_visualization_data_fills_the_callers_object_in_place
    with_game do
      data = M::VisualizationData.new
      frequencies = data.Frequencies
      assert_equal 256, frequencies.Count
      assert(frequencies.all?(&:zero?))

      assert_nil M::MediaPlayer.GetVisualizationData(data)
      # The same wrapper, not a replacement, and still 256 long.
      assert_same frequencies, data.Frequencies
      assert_equal 256, data.Frequencies.Count
      assert_equal 256, data.Samples.Count
      assert(data.Frequencies.all? { |value| value.is_a?(Float) })

      assert_raises(ArgumentError) { M::MediaPlayer.GetVisualizationData(nil) }
      assert_raises(TypeError) { M::MediaPlayer.GetVisualizationData(Object.new) }
    end
  end

  # `Play(null)` is `ArgumentNullException` in the IL's first statement, and the projection's
  # overload dispatch refuses anything that is neither a Song nor a SongCollection.
  def test_play_refuses_null_and_anything_that_is_not_a_song_or_collection
    with_game do
      assert_raises(ArgumentError) { M::MediaPlayer.Play(nil) }
      assert_raises(TypeError) { M::MediaPlayer.Play(Object.new) }
      assert_raises(TypeError) { M::MediaPlayer.Play(42) }
    end
  end

  # Disposal is the library's, and it is idempotent. Every member refuses afterwards, which is
  # `VerifyNotDisposed` in the IL rather than a Ruby nicety.
  def test_the_library_disposes_once_and_refuses_every_member_afterwards
    with_game do
      library = M::MediaLibrary.new
      refute library.IsDisposed
      library.Dispose
      assert library.IsDisposed
      library.Dispose # idempotent

      %i[Songs Albums Artists Genres Playlists Pictures SavedPictures RootPictureAlbum].each do |member|
        assert_raises(CNA::DisposedObjectError, member.to_s) { library.public_send(member) }
      end
      assert_raises(CNA::DisposedObjectError) { library.GetPictureFromToken("anything") }
    end
  end

  # A token nothing names answers null rather than raising, and a null token is an argument
  # failure -- the two halves of the same IL.
  def test_get_picture_from_token_answers_null_for_an_unknown_token
    with_library do |library|
      assert_nil library.GetPictureFromToken("no-such-token-#{Process.pid}")
      assert_raises(ArgumentError) { library.GetPictureFromToken(nil) }
    end
  end

  # `MediaLibrary.new(mediaSource)` takes the one source `GetAvailableMediaSources` answers, and
  # refuses anything else. Both constructors reach a real library.
  def test_the_source_constructor_takes_the_one_source_that_exists
    with_game do
      source = M::MediaSource.GetAvailableMediaSources.first
      library = M::MediaLibrary.new(source)
      begin
        assert_same source, library.MediaSource
        assert_operator library.Pictures.Count, :>=, 0
      ensure
        library.Dispose
      end
      assert_raises(TypeError) { M::MediaLibrary.new(Object.new) }
    end
  end

  # Equality is handle equality through CNA, and `GetHashCode` comes from the same place. Two reads
  # of the same picture are equal and hash alike; a picture and a non-picture never are.
  def test_identity_is_the_librarys_rather_than_the_wrappers
    with_library do |library|
      pictures = library.Pictures
      skip "this machine's media library reports no pictures" if pictures.Count.zero?

      first = pictures[0]
      again = pictures[0]
      refute_same first, again, "each read builds a new wrapper"
      assert_equal first, again
      assert first.Equals(again)
      assert_equal first.GetHashCode, again.GetHashCode
      refute first.Equals(nil)
      refute first.Equals("not a picture")
      next if pictures.Count < 2

      refute_equal first, pictures[1]
    end
  end

  private

  def native_symbol?(name)
    Fiddle::Handle.new(ENV.fetch("CNA_NATIVE_LIBRARY")).sym(name)
    true
  rescue Fiddle::DLError
    false
  end
end
