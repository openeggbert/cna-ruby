# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# Foundation 24 — AudioListener, AudioEmitter, PresentationParameters and
# GameComponentCollectionEventArgs, all derived from pinned XNA 4.0 Windows IL.
#
# Every one is a publicly constructible managed state holder with no native reachability. None of
# them starts an audio engine, creates a graphics device, looks up a window or raises an event.
class ManagedDescriptorsTest < Minitest::Test
  F = Microsoft::Xna::Framework
  A = F::Audio
  G = F::Graphics
  N = CNA::Runtime::Numeric

  ROOT = Pathname(__dir__).join("..").expand_path
  IL = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read).freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze

  NAMES = %w[
    Microsoft.Xna.Framework.Audio.AudioListener
    Microsoft.Xna.Framework.Audio.AudioEmitter
    Microsoft.Xna.Framework.Graphics.PresentationParameters
    Microsoft.Xna.Framework.GameComponentCollectionEventArgs
  ].freeze

  def test_every_type_is_complete_pure_managed_and_hash_pinned
    NAMES.each do |name|
      entry = IL.fetch("types").fetch(name)
      refute entry.fetch("nativeReachable"), name
      refute entry.fetch("declaresNativeEntryPoint"), name
      assert_includes IL.fetch("assemblies").map { |assembly| assembly.fetch("sha256") },
                      entry.fetch("assemblySha256"), name
      assert_includes STRICT.fetch("completeTypeNames"), name, name
      assert_equal 0, STRICT.fetch("localDiagnostics").fetch(name), name
    end
  end

  # --------------------------------------------------------------- AudioListener / AudioEmitter

  def spatial_types = [A::AudioListener.new, A::AudioEmitter.new]

  def test_the_constructor_stores_position_and_velocity_unflipped
    # FlipHandedness is (X, Y, -Z) and runs on both the getter and the setter. The constructor
    # stores Position and Velocity **unflipped**, so their first read negates a zero.
    spatial_types.each do |value|
      label = value.class.name
      assert_equal F::Vector3.Zero, value.Position, label
      assert_equal F::Vector3.Zero, value.Velocity, label
      assert_equal 0x8000_0000, N.f32_bits(value.Position.Z), "#{label} default Position.Z is negative zero"
      assert_equal 0x8000_0000, N.f32_bits(value.Velocity.Z), "#{label} default Velocity.Z is negative zero"
    end
  end

  def test_the_constructor_stores_forward_and_up_flipped_so_they_read_back_exactly
    spatial_types.each do |value|
      label = value.class.name
      assert_equal F::Vector3.Forward, value.Forward, label
      assert_equal F::Vector3.Up, value.Up, label
      # Forward is (0, 0, -1) and Up is (0, 1, 0): the double flip restores both exactly.
      assert_equal N.f32_bits(F::Vector3.Forward.Z), N.f32_bits(value.Forward.Z), label
      assert_equal N.f32_bits(F::Vector3.Up.Z), N.f32_bits(value.Up.Z), label
    end
  end

  def test_every_spatial_property_round_trips_and_answers_a_fresh_vector
    spatial_types.each do |value|
      %i[Position Velocity Forward Up].each do |name|
        vector = F::Vector3.new(1.5, -2.25, 3.75)
        value.public_send(:"#{name}=", vector)
        assert_equal vector, value.public_send(name), "#{value.class}##{name}"
        refute_same value.public_send(name), value.public_send(name)
        # The stored value is a copy: mutating the caller's vector must not reach it.
        vector.X = 99.0
        assert_equal 1.5, value.public_send(name).X
      end
    end
  end

  def test_spatial_setters_reject_a_non_vector3
    spatial_types.each do |value|
      %i[Position= Velocity= Forward= Up=].each do |setter|
        assert_raises(TypeError, "#{value.class}##{setter}") { value.public_send(setter, :not_a_vector) }
        assert_raises(TypeError, "#{value.class}##{setter}") { value.public_send(setter, F::Vector2.new(1, 2)) }
      end
    end
  end

  def test_the_listener_declares_exactly_the_four_spatial_properties
    assert_empty A::AudioListener.public_instance_methods(false)
    assert_equal %i[Forward Forward= Position Position= Up Up= Velocity Velocity=],
                 (A::AudioListener.public_instance_methods - Object.public_instance_methods).sort
  end

  def test_the_emitter_adds_doppler_scale_with_the_exact_il_boundary
    emitter = A::AudioEmitter.new
    assert_equal 1.0, emitter.DopplerScale

    # `ldarg.1; ldc.r4 0.0; bge.un.s` — the throw is skipped when the value is greater than or
    # equal to zero **or unordered**, so NaN and negative zero are both accepted.
    [0.0, -0.0, 1.5, 1_000_000.0, Float::INFINITY].each do |accepted|
      emitter.DopplerScale = accepted
      assert_equal accepted, emitter.DopplerScale, accepted.inspect
    end
    emitter.DopplerScale = Float::NAN
    assert emitter.DopplerScale.nan?, "NaN is unordered, so bge.un takes the branch past the throw"

    [-1.0, -0.000001, -Float::INFINITY].each do |rejected|
      assert_raises(RangeError, rejected.inspect) { emitter.DopplerScale = rejected }
    end
    # The rejected assignment leaves the previous value in place.
    assert emitter.DopplerScale.nan?
  end

  def test_the_emitter_exposes_no_internal_xact_field
    # ChannelCount, ChannelRadius and CurveDistanceScaler are set by the constructor but are
    # internal in XNA, so none is projected.
    %i[ChannelCount ChannelRadius CurveDistanceScaler].each do |absent|
      refute A::AudioEmitter.method_defined?(absent), absent.to_s
    end
    assert_equal %i[DopplerScale DopplerScale=], A::AudioEmitter.public_instance_methods(false).sort
  end

  def test_neither_audio_type_implies_an_audio_engine
    # `SoundEffect` and `SoundEffectInstance` exist now; what this milestone claimed, and still
    # claims, is that **it** built neither. The list narrows to the audio types nothing here has
    # built rather than being loosened.
    # The whole Audio namespace is projected now, so what this milestone claims is narrowed to
    # what it is really about: **it** built no engine, and nothing it added produces one.
    refute A::AudioListener.public_method_defined?(:Play)
    refute A::AudioEmitter.public_method_defined?(:Play)
    refute A::AudioListener.public_method_defined?(:GetCategory)
    refute A::AudioEmitter.public_method_defined?(:GetCategory)
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
  end

  # ------------------------------------------------------------------- PresentationParameters

  def test_the_constructor_stores_one_value_and_leaves_every_other_field_at_the_clr_default
    parameters = G::PresentationParameters.new
    assert_equal 0, parameters.BackBufferWidth
    assert_equal 0, parameters.BackBufferHeight
    assert_equal G::SurfaceFormat::Color, parameters.BackBufferFormat
    assert_equal G::DepthFormat::None, parameters.DepthStencilFormat
    assert_equal 0, parameters.MultiSampleCount
    assert_equal F::DisplayOrientation::Default, parameters.DisplayOrientation
    assert_equal G::PresentInterval::Default, parameters.PresentationInterval
    assert_equal G::RenderTargetUsage::DiscardContents, parameters.RenderTargetUsage
    assert_equal 0, parameters.DeviceWindowHandle
    # The constructor's only store is set_IsFullScreen(true).
    assert_equal true, parameters.IsFullScreen
  end

  def test_bounds_is_derived_from_the_back_buffer_and_answers_a_fresh_rectangle
    parameters = G::PresentationParameters.new
    assert_equal F::Rectangle.new(0, 0, 0, 0), parameters.Bounds
    parameters.BackBufferWidth = 1280
    parameters.BackBufferHeight = 720
    assert_equal F::Rectangle.new(0, 0, 1280, 720), parameters.Bounds
    refute_same parameters.Bounds, parameters.Bounds
    refute G::PresentationParameters.method_defined?(:Bounds=)
  end

  def test_every_setter_is_a_plain_store_with_only_boundary_validation
    parameters = G::PresentationParameters.new
    parameters.BackBufferWidth = -5
    parameters.BackBufferHeight = -7
    parameters.MultiSampleCount = -1
    # XNA validates nothing, so negative values are stored as given.
    assert_equal(-5, parameters.BackBufferWidth)
    assert_equal(-7, parameters.BackBufferHeight)
    assert_equal(-1, parameters.MultiSampleCount)
    assert_equal F::Rectangle.new(0, 0, -5, -7), parameters.Bounds

    assert_raises(RangeError) { parameters.BackBufferWidth = 2**31 }
    assert_raises(RangeError) { parameters.BackBufferFormat = 9999 }
    assert_raises(TypeError) { parameters.IsFullScreen = 1 }
    assert_raises(TypeError) { parameters.IsFullScreen = nil }
  end

  def test_the_device_window_handle_is_a_signed_native_pointer_width_integer
    parameters = G::PresentationParameters.new
    limit = 2**(N.pointer_width_bits - 1)
    parameters.DeviceWindowHandle = limit - 1
    assert_equal limit - 1, parameters.DeviceWindowHandle
    parameters.DeviceWindowHandle = -limit
    assert_equal(-limit, parameters.DeviceWindowHandle)
    assert_raises(RangeError) { parameters.DeviceWindowHandle = limit }
    assert_raises(RangeError) { parameters.DeviceWindowHandle = -limit - 1 }
    # Never a Fiddle::Pointer.
    assert_instance_of Integer, parameters.DeviceWindowHandle
  end

  def test_clone_copies_every_setting_including_the_constructor_default
    parameters = G::PresentationParameters.new
    parameters.BackBufferWidth = 800
    parameters.BackBufferHeight = 600
    parameters.BackBufferFormat = G::SurfaceFormat::Bgra4444
    parameters.DepthStencilFormat = G::DepthFormat::Depth24Stencil8
    parameters.MultiSampleCount = 4
    parameters.DisplayOrientation = F::DisplayOrientation::LandscapeLeft
    parameters.PresentationInterval = G::PresentInterval::Two
    parameters.RenderTargetUsage = G::RenderTargetUsage::PreserveContents
    parameters.DeviceWindowHandle = 4242
    # The clone's own constructor sets IsFullScreen true, and the settings copy overwrites it.
    parameters.IsFullScreen = false

    copy = parameters.Clone
    refute_same copy, parameters
    assert_instance_of G::PresentationParameters, copy
    %i[BackBufferWidth BackBufferHeight BackBufferFormat DepthStencilFormat MultiSampleCount
       DisplayOrientation PresentationInterval RenderTargetUsage DeviceWindowHandle
       IsFullScreen].each do |name|
      assert_equal parameters.public_send(name), copy.public_send(name), name.to_s
    end
    copy.BackBufferWidth = 1
    assert_equal 800, parameters.BackBufferWidth
  end

  def test_presentation_parameters_implies_no_device_adapter_or_swap_chain
    # `DepthStencilState` left this list when the four state objects were built. It is a managed
    # value holder with no device, no adapter and no swap chain in it, so what this test claims is
    # unchanged and is now stated by the device's own surface rather than by that type's absence.
    %i[GraphicsAdapter RenderTarget2D
       RenderTargetCube].each { |absent| refute G.const_defined?(absent, false), "Graphics::#{absent}" }
    assert_equal %i[IsDisposed Viewport Clear Textures VertexTextures].sort, G::GraphicsDevice.public_instance_methods(false).sort
  end

  # -------------------------------------------------------- GameComponentCollectionEventArgs

  def test_the_event_args_subclass_stores_its_component_and_validates_the_clr_type
    host = Class.new { include F::IGameComponent }
    component = host.new
    args = F::GameComponentCollectionEventArgs.new(component)
    assert_same component, args.GameComponent
    assert_equal CNA::Runtime::EventArgs, F::GameComponentCollectionEventArgs.superclass
    assert_kind_of CNA::Runtime::EventArgs, args
    # XNA validates nothing, so null is accepted.
    assert_nil F::GameComponentCollectionEventArgs.new(nil).GameComponent
    assert_raises(TypeError) { F::GameComponentCollectionEventArgs.new(5) }
    assert_raises(ArgumentError) { F::GameComponentCollectionEventArgs.new }
    assert_equal %i[GameComponent], F::GameComponentCollectionEventArgs.public_instance_methods(false).sort
    refute F::GameComponentCollectionEventArgs.method_defined?(:GameComponent=)
  end

  # ------------------------------------------------ Foundation 25: constructor-free classes

  CONSTRUCTOR_FREE = %w[
    Microsoft.Xna.Framework.Graphics.DisplayMode
    Microsoft.Xna.Framework.Graphics.ResourceCreatedEventArgs
    Microsoft.Xna.Framework.Graphics.ResourceDestroyedEventArgs
  ].freeze

  def test_a_class_whose_only_constructor_is_internal_projects_with_new_made_private
    CONSTRUCTOR_FREE.each do |name|
      runtime = name.split(".").reduce(Object) { |scope, part| scope.const_get(part, false) }
      refute runtime.respond_to?(:new), "#{name}.new must not be public"
      assert_raises(NoMethodError, name) { runtime.new }
      # The internal construction path the CLR gives a future producer stays reachable.
      assert runtime.respond_to?(:new, true), name
      assert_includes STRICT.fetch("completeTypeNames"), name, name
      assert_equal 0, STRICT.fetch("localDiagnostics").fetch(name), name
      # The pinned IL agrees: exactly one constructor, and it is assembly-scoped.
      constructors = IL.fetch("types").fetch(name).fetch("constructors")
      assert_equal 1, constructors.length, name
      assert_equal "assembly", constructors.first.fetch("access"), name
    end
  end

  def display_mode(width, height, format = G::SurfaceFormat::Color)
    G::DisplayMode.__send__(:new, width, height, format)
  end

  def test_display_mode_stores_three_values_and_derives_the_rest
    mode = display_mode(1920, 1080)
    assert_equal 1920, mode.Width
    assert_equal 1080, mode.Height
    assert_equal G::SurfaceFormat::Color, mode.Format
    assert_equal F::Rectangle.new(0, 0, 1920, 1080), mode.TitleSafeArea
    refute_same mode.TitleSafeArea, mode.TitleSafeArea
    refute G::DisplayMode.method_defined?(:Width=)
  end

  def test_display_mode_aspect_ratio_answers_zero_when_either_extent_is_zero
    # `brfalse` on height then `brtrue` on width: either zero answers 0, otherwise both convert to
    # Single and divide in Single.
    assert_equal 0.0, display_mode(0, 1080).AspectRatio
    assert_equal 0.0, display_mode(1920, 0).AspectRatio
    assert_equal 0.0, display_mode(0, 0).AspectRatio
    assert_equal N.div32(N.f32(1920), N.f32(1080)), display_mode(1920, 1080).AspectRatio
    assert_equal N.div32(N.f32(1024), N.f32(768)), display_mode(1024, 768).AspectRatio
    # Nothing validates the extents, so negatives divide as given.
    assert_equal N.div32(N.f32(-4), N.f32(2)), display_mode(-4, 2).AspectRatio
  end

  def test_display_mode_to_string_is_the_four_field_format
    assert_equal "{Width:1920 Height:1080 Format:Color AspectRatio:1.777778}",
                 display_mode(1920, 1080).ToString
    assert_equal display_mode(1920, 1080).ToString, display_mode(1920, 1080).to_s
    assert_equal "{Width:0 Height:0 Format:Color AspectRatio:0}", display_mode(0, 0).ToString
  end

  def test_the_resource_event_args_store_what_their_internal_constructors_take
    created = G::ResourceCreatedEventArgs.__send__(:new, :the_resource)
    assert_same :the_resource, created.Resource
    assert_equal CNA::Runtime::EventArgs, G::ResourceCreatedEventArgs.superclass
    assert_equal %i[Resource], G::ResourceCreatedEventArgs.public_instance_methods(false)

    # `.ctor(string name, object tag)` stores tag first, then name; both properties are get-only.
    destroyed = G::ResourceDestroyedEventArgs.__send__(:new, "surface", :the_tag)
    assert_equal "surface", destroyed.Name
    assert_same :the_tag, destroyed.Tag
    assert_equal %i[Name Tag], G::ResourceDestroyedEventArgs.public_instance_methods(false).sort
    assert_nil G::ResourceDestroyedEventArgs.__send__(:new, nil, nil).Name
  end

  # ------------------------------------------------------- Foundation 26: DisplayModeCollection

  def collection(*triples)
    modes = triples.map { |width, height, format| display_mode(width, height, format) }
    G::DisplayModeCollection.__send__(:new, modes)
  end

  def test_the_collection_projects_exactly_its_two_declared_identities
    assert_equal %i[GetEnumerator []].sort, G::DisplayModeCollection.public_instance_methods(false).sort
    refute G::DisplayModeCollection.respond_to?(:new)
    # Like CurveKeyCollection it does not mix in Ruby Enumerable, which would add helper surface
    # unrelated to XNA.
    refute_includes G::DisplayModeCollection.ancestors, Enumerable
    refute G::DisplayModeCollection.method_defined?(:each)
    assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.Graphics.DisplayModeCollection"
    assert_equal 0, STRICT.fetch("localDiagnostics").fetch("Microsoft.Xna.Framework.Graphics.DisplayModeCollection")
  end

  def test_get_enumerator_walks_the_backing_list_in_order
    modes = collection([1920, 1080, G::SurfaceFormat::Color], [1280, 720, G::SurfaceFormat::Color],
                       [800, 600, G::SurfaceFormat::Bgra4444])
    assert_equal [1920, 1280, 800], modes.GetEnumerator.to_a.map(&:Width)
    # A fresh Enumerator every call, and no fabricated System namespace.
    refute_same modes.GetEnumerator, modes.GetEnumerator
    assert_instance_of Enumerator, modes.GetEnumerator
    assert_empty collection.GetEnumerator.to_a
  end

  def test_the_indexer_materialises_the_modes_of_one_format_in_order
    modes = collection([1920, 1080, G::SurfaceFormat::Color], [800, 600, G::SurfaceFormat::Bgra4444],
                       [1280, 720, G::SurfaceFormat::Color])
    assert_equal [1920, 1280], modes[G::SurfaceFormat::Color].to_a.map(&:Width)
    assert_equal [800], modes[G::SurfaceFormat::Bgra4444].to_a.map(&:Width)
    # A format nothing matches answers an empty sequence, never nil.
    assert_empty modes[G::SurfaceFormat::Alpha8].to_a
    assert_instance_of Enumerator, modes[G::SurfaceFormat::Alpha8]
    assert_raises(RangeError) { modes[9999] }
  end

  def test_the_collection_backing_list_is_not_reachable_or_mutable
    modes = [display_mode(640, 480)]
    collection = G::DisplayModeCollection.__send__(:new, modes)
    modes << display_mode(1024, 768)
    assert_equal 1, collection.GetEnumerator.to_a.length, "the collection copied the list it was given"
    assert_raises(TypeError) { G::DisplayModeCollection.__send__(:new, [1]) }
    assert_raises(TypeError) { G::DisplayModeCollection.__send__(:new, :not_an_array) }
  end

  def test_no_producer_for_any_constructor_free_class_is_fabricated
    # GraphicsAdapter would enumerate DisplayMode; GraphicsDevice.ResourceCreated/ResourceDestroyed
    # would raise the two EventArgs types. All three producers stay absent.
    refute G.const_defined?(:GraphicsAdapter, false)
    %i[ResourceCreated ResourceDestroyed].each do |absent|
      refute G::GraphicsDevice.method_defined?(absent), absent.to_s
    end
    assert_equal %i[IsDisposed Viewport Clear Textures VertexTextures].sort, G::GraphicsDevice.public_instance_methods(false).sort
  end

  # The event args type still implies neither component class. GameComponentCollection exists as of
  # Foundation 35, from its own IL rather than from anything this type implies, and the relation
  # runs the other way: the collection constructs these args, so it names the type and not the
  # reverse.
  # The event args type still implies neither the collection nor the component class. Both exist
  # now -- Foundation 35 and 38 -- each from its own IL rather than from anything this type implies,
  # and the relation runs the other way: the collection constructs these args, so it names the type
  # and not the reverse. DrawableGameComponent, which this type does not name at all, is still
  # absent.
  def test_the_event_args_type_implies_no_game_component_family
    refute F.const_defined?(:DrawableGameComponent, false)
    assert F.const_defined?(:GameComponentCollection, false)
    assert F.const_defined?(:GameComponent, false)
    assert_nil F::GameComponentCollectionEventArgs.new(nil).GameComponent

    # Nothing in the args type's own contract names either class: its one property is typed
    # IGameComponent, the contract, not GameComponent, the implementation.
    reference = JSON.parse(ROOT.join("tools", "api_compat", "reference",
                                     "xna40-windows-runtime-contract.json").read)
    args = reference.fetch("types")
                    .find { |type| type.fetch("name") == "Microsoft.Xna.Framework.GameComponentCollectionEventArgs" }
    signatures = args.fetch("members").flat_map do |member|
      [member["type"], member["returnType"], *member.fetch("parameters", []).map { |p| p["type"] }]
    end.compact
    refute(signatures.any? { |signature| signature.end_with?(".GameComponent") })
    assert(signatures.any? { |signature| signature.end_with?(".IGameComponent") })
  end
end
