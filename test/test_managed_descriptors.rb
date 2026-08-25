# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
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
    %i[SoundEffect SoundEffectInstance Microphone AudioEngine WaveBank SoundBank Cue AudioCategory]
      .each { |absent| refute A.const_defined?(absent, false), "Audio::#{absent}" }
    assert_equal 38, CNA::Native::Manifest::FUNCTIONS.length
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
    %i[GraphicsAdapter DisplayMode DisplayModeCollection RenderTarget2D RenderTargetCube
       DepthStencilState].each { |absent| refute G.const_defined?(absent, false), "Graphics::#{absent}" }
    assert_equal %i[IsDisposed Viewport Clear].sort, G::GraphicsDevice.public_instance_methods(false).sort
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

  def test_the_event_args_type_implies_no_game_component_family
    %i[GameComponent DrawableGameComponent GameComponentCollection]
      .each { |absent| refute F.const_defined?(absent, false), "Framework::#{absent}" }
  end
end
