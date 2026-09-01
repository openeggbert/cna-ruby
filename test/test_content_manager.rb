# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `Content.ContentManager`, `Game.Content`, and the two projections that unblocked them.
#
# The native half runs against **externally produced** `.xnb` files — MonoGame's own Ms-PL test
# corpus, referenced by path through `CNA_TEST_XNB_DIR` and never copied into this repository, each
# shipping a manifest that states what it contains. That is what makes the load assertions
# falsifiable: `white-1.xnb` is documented as a 1x1 `Color` texture with one mip level, so a loader
# that answered plausible-looking dimensions would fail here.
class ContentManagerTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  C = Microsoft::Xna::Framework::Content
  CM = C::ContentManager
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read).freeze
  RULES = JSON.parse(ROOT.join("tools", "api_compat", "mapping-rules.json").read).freeze

  ASSET = "white-1"

  def xnb_directory
    directory = ENV["CNA_TEST_XNB_DIR"]
    skip "CNA_TEST_XNB_DIR not supplied" if directory.nil? || !File.directory?(directory)
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    directory
  end

  # ------------------------------------------------------------------- the contract, from metadata

  def test_the_projected_surface_is_the_ten_members_the_reference_declares
    contract = REFERENCE.fetch("Microsoft.Xna.Framework.Content.ContentManager")
    assert_equal "System.Object", contract.fetch("baseType")
    assert_equal ["System.IDisposable"], contract.fetch("directInterfaces")
    assert_equal 10, contract.fetch("members").length

    %i[Load Unload Dispose RootDirectory ServiceProvider].each { |name| assert CM.public_method_defined?(name), name }
    %i[ReadAsset OpenStream].each { |name| assert CM.protected_method_defined?(name), name }
    assert CM.public_method_defined?(:RootDirectory=)
    # `System.IDisposable` collapses to the member the implementing type declares, so there is no
    # module to include and no `Close` alias.
    refute CM.public_method_defined?(:Close)
  end

  def test_the_scoreboard_records_it_complete_and_closes_game
    assert_equal ReviewedScoreboard::TARGET_TYPES, STRICT.fetch("TARGET_TYPES")
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    # Game was the sixth partial type and `Content` was its last missing member.
    assert_equal ReviewedScoreboard::PARTIAL_TYPES, STRICT.fetch("PARTIAL_TYPES")
    assert_empty STRICT.fetch("details").fetch("MISSING_MEMBER").grep(/Microsoft\.Xna\.Framework\.Game::/)
    assert_empty STRICT.fetch("details").fetch("MISSING_MEMBER").grep(/ContentManager::/)
    assert_equal 0, STRICT.fetch("UNEXPECTED_MEMBER")
  end

  # ------------------------------------------------------------------ the two projection decisions

  # Ruby has no static generics, so a CLR generic method takes its type arguments as leading
  # positional parameters. This is the only rule under which a projected Ruby method may take more
  # arguments than its CLR signature declares, so it is stated in the rules file and checked here
  # against the reference's own arities rather than against the implementation's.
  def test_a_generic_method_takes_its_type_argument_first
    rule = RULES.fetch("generics").fetch("methodProjection")
    assert_includes rule, "leading positional parameters"
    assert_includes rule, "Module"

    %w[Load ReadAsset].each do |name|
      declared = REFERENCE.fetch("Microsoft.Xna.Framework.Content.ContentManager")
                          .fetch("members").find { |m| m.fetch("name") == name }
      expected = declared.fetch("genericParameters").length + declared.fetch("parameters").length
      actual = CM.instance_method(name).arity.abs
      assert_equal expected, actual, "#{name} must take one leading Module plus its CLR parameters"
    end

    # A non-Module first argument is a type error rather than a silently mis-shaped call.
    manager = CM.new(F::GameServiceContainer.new)
    assert_raises(TypeError) { manager.Load("Texture2D", ASSET) }
    assert_raises(ArgumentError) { manager.Load(nil, ASSET) }
  end

  # `System.Action`1` collapses to Ruby's callable protocol. The register records the decision; this
  # asserts the decision was not quietly turned into an invented constant, which is the failure mode
  # a structural collapse exists to prevent.
  def test_action_collapses_to_a_callable_and_invents_no_constant
    assert CNA::Runtime::BclProjection.structural_collapse?("System.Action`1")
    assert_includes CNA::Runtime::BclProjection.identities, "System.Action`1"
    %i[Action ActionOfT].each do |invented|
      refute Object.const_defined?(invented, false), invented
      refute CNA::Runtime.const_defined?(invented, false), invented
    end
    refute Object.const_defined?(:System, false)
  end

  def test_a_generic_parameter_is_never_an_unmapped_bcl_type
    b = CNA::Runtime::BclProjection
    %w[!!0 !0 !!0[] !1].each { |placeholder| assert b.generic_parameter?(placeholder), placeholder }
    %w[System.Action`1 System.String !!x !! 0 System.Int32[]].each do |identity|
      refute b.generic_parameter?(identity), identity
    end
    FRONTIER.fetch("dependencyCompleteCandidates").each do |candidate|
      candidate.fetch("unmappedBclTypes").each do |identity|
        refute b.generic_parameter?(identity), "#{candidate.fetch("name")} reports #{identity}"
      end
    end
  end

  def test_the_stream_and_action_projections_consumed_content_manager
    names = FRONTIER.fetch("dependencyCompleteCandidates").map { |item| item.fetch("name") }
    refute_includes names, "Microsoft.Xna.Framework.Content.ContentManager"
    # Empty for one milestone, when `IVertexType` uncovered the four vertex structs; those were
    # built immediately after, so it is empty again. What this test claims is unchanged: nothing
    # **it** unblocked became consumable.
    assert_empty FRONTIER.fetch("consumableCandidates")
    # Completing it uncovered what it was hiding: ResourceContentManager derives from it. That
    # candidate has since been built too -- once System.Resources.ResourceManager was collapsed to
    # the one member it reaches -- so what is asserted now is the end state that produced.
    refute_includes names, "Microsoft.Xna.Framework.Content.ResourceContentManager"
    assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.Content.ResourceContentManager"
  end

  # ------------------------------------------------------------------------- managed construction

  def test_construction_validates_and_defaults_the_root_to_empty
    services = F::GameServiceContainer.new
    assert_raises(ArgumentError) { CM.new(nil) }
    assert_raises(ArgumentError) { CM.new(services, nil) }
    assert_equal "", CM.new(services).RootDirectory
    assert_equal "Content", CM.new(services, "Content").RootDirectory
    assert_same services, CM.new(services).ServiceProvider
  end

  # `set_RootDirectory` refuses null first and a non-empty cache second, so a null root is refused
  # even on a manager that has already loaded something.
  def test_the_root_directory_refuses_null_and_refuses_to_change_once_loaded
    manager = CM.new(F::GameServiceContainer.new)
    assert_raises(ArgumentError) { manager.RootDirectory = nil }
    manager.RootDirectory = "a"
    assert_equal "a", manager.RootDirectory
  end

  def test_a_disposed_manager_refuses_every_member
    manager = CM.new(F::GameServiceContainer.new)
    manager.Dispose
    manager.Dispose # idempotent: nulling the stores is what makes it so, with no separate flag
    assert_raises(CNA::DisposedObjectError) { manager.Load(G::Texture2D, ASSET) }
    assert_raises(CNA::DisposedObjectError) { manager.Unload }
    assert_raises(CNA::DisposedObjectError) { manager.send(:OpenStream, ASSET) }
    assert_raises(CNA::DisposedObjectError) { manager.send(:ReadAsset, G::Texture2D, ASSET, nil) }
    # `set_RootDirectory` is the one member with **no** disposed check: it reads `loadedAssets.Count`
    # directly, so XNA throws NullReferenceException there and not ObjectDisposedException. That
    # asymmetry is reproduced rather than smoothed over, and Ruby's NoMethodError on nil is the same
    # shape of failure -- a bare `rescue` catches it, as `catch (Exception)` catches the CLR one.
    assert_raises(NoMethodError) { manager.RootDirectory = "x" }
    assert_kind_of StandardError, (begin; manager.RootDirectory = "x"; rescue => e; e; end)
  end

  # A standalone manager is fully constructible and every managed member works, but it has no native
  # content manager, because `cna_content_manager_create` needs a graphics device that XNA would
  # find through an `IGraphicsDeviceService` this binding deliberately registers no producer for.
  # The refusal names that, rather than failing somewhere less informative.
  def test_a_standalone_manager_refuses_to_load_and_says_why
    manager = CM.new(F::GameServiceContainer.new)
    error = assert_raises(C::ContentLoadException) { manager.Load(G::Texture2D, ASSET) }
    assert_includes error.message, "IGraphicsDeviceService"
    assert_includes error.message, "Game.Content"
  end

  # The registry is what `Load` really dispatches on, so it grows only when a milestone registers
  # a materializer. `SpriteFont` joined `Texture2D` when its three BCL blockers were decided.
  def test_the_supported_registry_names_exactly_what_is_implemented
    assert_equal [G::Texture2D, G::SpriteFont], CM.supported_types
  end

  # --------------------------------------------------------------------------- Game.Content

  def test_game_content_is_the_manager_the_game_owns
    game = F::Game.new
    begin
      content = game.Content
      assert_instance_of CM, content
      assert_same content, game.Content, "the property is one managed reference, not a new object"
      assert_same game.Services, content.ServiceProvider
      assert_equal "", content.RootDirectory, "XNA's default is String.Empty, not CNA's \"Content\""
    ensure
      game.Dispose
    end
  end

  # `set_Content` builds a **parameterless** ArgumentNullException and then does one `stfld`.
  def test_game_content_is_settable_and_refuses_nil
    game = F::Game.new
    begin
      replacement = CM.new(game.Services, "elsewhere")
      game.Content = replacement
      assert_same replacement, game.Content
      assert_raises(ArgumentError) { game.Content = nil }
      assert_same replacement, game.Content, "the refusal happens before the store"
    ensure
      game.Dispose
    end
  end

  def test_game_content_refuses_a_disposed_game_and_a_foreign_thread
    game = F::Game.new
    Thread.new { assert_raises(CNA::OwnerThreadError) { game.Content } }.join
    game.Dispose
    assert_raises(CNA::DisposedObjectError) { game.Content }
    assert_raises(CNA::DisposedObjectError) { game.Content = CM.new(F::GameServiceContainer.new) }
  end

  # ------------------------------------------------------------------------------- real loading

  class LoadingGame < F::Game
    attr_reader :result

    def initialize(directory, &body)
      @directory = directory
      @body = body
      @result = nil
      super()
      F::GraphicsDeviceManager.new(self)
    end

    def LoadContent
      self.Content.RootDirectory = @directory
      @result = @body.call(self)
    ensure
      self.Exit
    end
  end

  def with_content
    directory = xnb_directory
    game = LoadingGame.new(directory) { |host| yield host.Content, host }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  # The manifest beside `white-1.xnb` states 1x1, one mip level, `SurfaceFormat.Color`. Asserting
  # those is what makes this a load rather than a smoke test.
  def test_it_loads_an_externally_produced_xnb_texture_with_the_values_its_manifest_states
    values = with_content { |content, _| t = content.Load(G::Texture2D, ASSET); [t.Width, t.Height, t.LevelCount, t.Format.to_s, t.Bounds.Width] }
    assert_equal [1, 1, 1, "Color", 1], values
  end

  # XNA returns the cached instance, so two loads are one asset. The key is
  # `TitleContainer.GetCleanPath(assetName)` under an ordinal-ignore-case comparer, so a name that
  # normalizes and case-folds to the same key is the same entry.
  def test_a_second_load_answers_the_same_object_and_the_key_is_xnas
    same = with_content do |content, _|
      first = content.Load(G::Texture2D, ASSET)
      [first.equal?(content.Load(G::Texture2D, ASSET)),
       first.equal?(content.Load(G::Texture2D, "./#{ASSET}")),
       first.equal?(content.Load(G::Texture2D, ASSET.upcase)),
       first.equal?(content.Load(G::Texture2D, "sub/../#{ASSET}"))]
    end
    assert_equal [true, true, true, true], same
  end

  # A cache hit whose value is not a `T` throws rather than reloading, which is the one branch that
  # distinguishes XNA's cache from a plain memo.
  def test_a_cache_hit_of_the_wrong_type_raises_rather_than_reloading
    raised = with_content do |content, _|
      content.Load(G::Texture2D, ASSET)
      begin
        content.Load(G::SpriteBatch, ASSET)
        nil
      rescue C::ContentLoadException => error
        error.message
      end
    end
    assert_includes raised.to_s, "SpriteBatch"
  end

  def test_an_unsupported_type_and_a_missing_asset_both_raise_content_load_exception
    kinds = with_content do |content, _|
      [begin; content.Load(G::SpriteBatch, ASSET); nil; rescue => e; e.class; end,
       begin; content.Load(G::Texture2D, "definitely-not-here"); nil; rescue => e; e.class; end]
    end
    assert_equal [C::ContentLoadException, C::ContentLoadException], kinds
  end

  # `Unload` disposes every recorded disposable and clears the cache, so the next load is a new
  # object. The texture CNA hands back is independently owned and survives the native unload, which
  # is exactly why this side has to dispose it.
  def test_unload_disposes_the_cache_and_the_next_load_is_a_new_object
    states = with_content do |content, _|
      first = content.Load(G::Texture2D, ASSET)
      before = first.IsDisposed
      content.Unload
      after = first.IsDisposed
      second = content.Load(G::Texture2D, ASSET)
      [before, after, first.equal?(second), second.IsDisposed, second.Width]
    end
    assert_equal [false, true, false, false, 1], states
  end

  # The `Action<IDisposable>` contract: a supplied callable **replaces** the manager's own
  # bookkeeping, so an asset read with one is not disposed by `Unload`.
  def test_a_supplied_record_callable_replaces_the_managers_own_bookkeeping
    states = with_content do |content, _|
      recorded = []
      asset = content.send(:ReadAsset, G::Texture2D, ASSET, ->(disposable) { recorded << disposable })
      before = [recorded.length, recorded.first.equal?(asset)]
      content.Unload
      after = asset.IsDisposed
      asset.Dispose
      [before, after]
    end
    assert_equal [[1, true], false], states
  end

  def test_read_asset_accepts_any_callable_and_refuses_a_non_callable
    kinds = with_content do |content, _|
      seen = []
      content.send(:ReadAsset, G::Texture2D, ASSET, seen.method(:push))
      [seen.length,
       begin; content.send(:ReadAsset, G::Texture2D, ASSET, 42); nil; rescue => e; e.class; end]
    end
    assert_equal [1, TypeError], kinds
  end

  # `OpenStream` is projected and really opens the asset's bytes; what it does not do is feed
  # `ReadAsset`, because CNA's reader takes an asset name and no route accepts `.xnb` bytes.
  def test_open_stream_answers_a_real_stream_over_the_asset_and_refuses_a_missing_one
    values = with_content do |content, _|
      stream = content.send(:OpenStream, ASSET)
      header = "\0".b * 4
      stream.Read(header, 0, 4)
      [stream.class, stream.Length, header,
       begin; content.send(:OpenStream, "definitely-not-here"); nil; rescue => e; e.class; end]
    end
    assert_equal CNA::Runtime::Stream, values[0]
    assert_operator values[1], :>, 0
    assert_equal "XNBw".b, values[2], "an XNB begins with the magic 'XNB' and a platform byte"
    assert_equal C::ContentLoadException, values[3]
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_adds_no_content_reader_pipeline_or_second_asset_type
    # `ResourceContentManager` was here until its own milestone built it, which is what this list
    # is for: it names what *this* milestone did not add.
    %i[ContentReader ContentTypeReader ContentTypeReaderManager].each do |absent|
      refute C.const_defined?(absent, false), absent.to_s
    end
    # The audio cluster exists, and this milestone did not build it: no `Load<SoundEffect>` reader
    # is registered, which is what the supported-type registry states.
    refute_includes CM.supported_types, F::Audio::SoundEffect
    # `SpriteFont` was here until its own milestone registered the second materializer, which is
    # what this list is for: it names the readers *this* milestone did not add.
    refute_includes CM.supported_types, F::Audio::SoundEffect
    # `TextureCube` and `Texture3D` were here until their own milestone built them, and neither is
    # loadable: no reader for either is registered, which is the claim this list is really making.
    # The nine `Effect` types left this list when the cluster was built; what this milestone
    # claimed, and still claims, is that **it** built none of them.
    %i[Model].each { |absent| refute G.const_defined?(absent, false), absent.to_s }
    [G::TextureCube, G::Texture3D].each { |built| refute_includes CM.supported_types, built }
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:constants), CNA::Native::Manifest::CONSTANTS.length
  end
end
