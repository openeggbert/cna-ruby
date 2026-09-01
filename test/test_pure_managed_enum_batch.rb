# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require_relative "reviewed_measurements"
require_relative "../lib/microsoft/xna/framework/audio"
require_relative "../lib/microsoft/xna/framework/graphics"
require_relative "../lib/microsoft/xna/framework/input"
require_relative "../lib/microsoft/xna/framework/input/touch"
require_relative "../lib/microsoft/xna/framework/media"

# Shared pure managed enum battery.
#
# Covers the Foundation 16 PURE MANAGED BATCH A enums and the two Foundation 17 Input.Touch enums.
# Every entry is one dependency-complete pure managed XNA enum closed through the unchanged
# CNA::Runtime::EnumValue / EnumType policy. The literal table below is the pinned expectation:
# it is compared against the retained XNA 4.0 Windows reference contract, against the generated
# selected surface, and against the Ruby runtime, so a wrong raw value fails in three places.
class PureManagedEnumBatchTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = F::Graphics
  I = F::Input
  A = F::Audio
  M = F::Media
  T = F::Input::Touch

  # Values are listed in pinned CLR declaration order, which is not always ascending raw order.
  BATCH = [
    ["Microsoft.Xna.Framework.Graphics.CubeMapFace", false,
     {"PositiveX" => 0, "NegativeX" => 1, "PositiveY" => 2,
      "NegativeY" => 3, "PositiveZ" => 4, "NegativeZ" => 5}],
    ["Microsoft.Xna.Framework.Audio.AudioChannels", false,
     {"Mono" => 1, "Stereo" => 2}],
    ["Microsoft.Xna.Framework.Audio.AudioStopOptions", false,
     {"AsAuthored" => 0, "Immediate" => 1}],
    ["Microsoft.Xna.Framework.Audio.MicrophoneState", false,
     {"Started" => 0, "Stopped" => 1}],
    ["Microsoft.Xna.Framework.Graphics.BufferUsage", true,
     {"None" => 0, "WriteOnly" => 1}],
    ["Microsoft.Xna.Framework.Graphics.FillMode", false,
     {"Solid" => 0, "WireFrame" => 1}],
    ["Microsoft.Xna.Framework.Graphics.IndexElementSize", false,
     {"SixteenBits" => 0, "ThirtyTwoBits" => 1}],
    ["Microsoft.Xna.Framework.Media.MediaSourceType", false,
     {"LocalDevice" => 0, "WindowsMediaConnect" => 4}],
    ["Microsoft.Xna.Framework.Audio.SoundState", false,
     {"Playing" => 0, "Paused" => 1, "Stopped" => 2}],
    ["Microsoft.Xna.Framework.Graphics.CullMode", false,
     {"None" => 0, "CullClockwiseFace" => 1, "CullCounterClockwiseFace" => 2}],
    ["Microsoft.Xna.Framework.Graphics.RenderTargetUsage", false,
     {"DiscardContents" => 0, "PreserveContents" => 1, "PlatformContents" => 2}],
    ["Microsoft.Xna.Framework.Graphics.SetDataOptions", true,
     {"None" => 0, "Discard" => 1, "NoOverwrite" => 2}],
    ["Microsoft.Xna.Framework.Graphics.TextureAddressMode", false,
     {"Wrap" => 0, "Clamp" => 1, "Mirror" => 2}],
    ["Microsoft.Xna.Framework.Media.MediaState", false,
     {"Paused" => 2, "Playing" => 1, "Stopped" => 0}],
    ["Microsoft.Xna.Framework.Media.VideoSoundtrackType", false,
     {"Music" => 0, "Dialog" => 1, "MusicAndDialog" => 2}],
    ["Microsoft.Xna.Framework.Graphics.PresentInterval", false,
     {"Default" => 0, "One" => 1, "Two" => 2, "Immediate" => 3}],
    ["Microsoft.Xna.Framework.Graphics.BlendFunction", false,
     {"Add" => 0, "Subtract" => 1, "ReverseSubtract" => 2, "Min" => 3, "Max" => 4}],
    ["Microsoft.Xna.Framework.Graphics.EffectParameterClass", false,
     {"Scalar" => 0, "Vector" => 1, "Matrix" => 2, "Object" => 3, "Struct" => 4}],
    ["Microsoft.Xna.Framework.Graphics.ColorWriteChannels", true,
     {"None" => 0, "Red" => 1, "Green" => 2, "Blue" => 4, "Alpha" => 8, "All" => 15}],
    ["Microsoft.Xna.Framework.Graphics.CompareFunction", false,
     {"Always" => 0, "Never" => 1, "Less" => 2, "LessEqual" => 3,
      "Equal" => 4, "GreaterEqual" => 5, "Greater" => 6, "NotEqual" => 7}],
    ["Microsoft.Xna.Framework.Graphics.StencilOperation", false,
     {"Keep" => 0, "Zero" => 1, "Replace" => 2, "Increment" => 3, "Decrement" => 4,
      "IncrementSaturation" => 5, "DecrementSaturation" => 6, "Invert" => 7}],
    ["Microsoft.Xna.Framework.Graphics.TextureFilter", false,
     {"Linear" => 0, "Point" => 1, "Anisotropic" => 2, "LinearMipPoint" => 3,
      "PointMipLinear" => 4, "MinLinearMagPointMipLinear" => 5,
      "MinLinearMagPointMipPoint" => 6, "MinPointMagLinearMipLinear" => 7,
      "MinPointMagLinearMipPoint" => 8}],
    ["Microsoft.Xna.Framework.Graphics.EffectParameterType", false,
     {"Void" => 0, "Bool" => 1, "Int32" => 2, "Single" => 3, "String" => 4,
      "Texture" => 5, "Texture1D" => 6, "Texture2D" => 7, "Texture3D" => 8,
      "TextureCube" => 9}],
    ["Microsoft.Xna.Framework.Graphics.Blend", false,
     {"One" => 0, "Zero" => 1, "SourceColor" => 2, "InverseSourceColor" => 3,
      "SourceAlpha" => 4, "InverseSourceAlpha" => 5, "DestinationColor" => 6,
      "InverseDestinationColor" => 7, "DestinationAlpha" => 8,
      "InverseDestinationAlpha" => 9, "BlendFactor" => 10, "InverseBlendFactor" => 11,
      "SourceAlphaSaturation" => 12}],
    # Foundation 17 — Input.Touch closure.
    ["Microsoft.Xna.Framework.Input.Touch.TouchLocationState", false,
     {"Invalid" => 0, "Released" => 1, "Pressed" => 2, "Moved" => 3}],
    ["Microsoft.Xna.Framework.Input.Touch.GestureType", true,
     {"None" => 0, "Tap" => 1, "DoubleTap" => 2, "Hold" => 4, "HorizontalDrag" => 8,
      "VerticalDrag" => 16, "FreeDrag" => 32, "Pinch" => 64, "Flick" => 128,
      "DragComplete" => 256, "PinchComplete" => 512}]
  ].freeze

  FOUNDATION16_BATCH = BATCH.reject { |clr, _flags, _values| clr.include?(".Input.Touch.") }.freeze
  FOUNDATION17_TOUCH = BATCH.select { |clr, _flags, _values| clr.include?(".Input.Touch.") }.freeze

  REFERENCE = JSON.parse(
    Pathname(__dir__).join("..", "tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze

  SIGNATURES = JSON.parse(
    Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze

  # Neighbouring enums that already existed before this batch. Every batch value is checked
  # against them so that a raw-value collision can never produce cross-type equality.
  FOREIGN = lambda do
    [G::DepthFormat::Depth24, G::SurfaceFormat::Color, G::SpriteSortMode::Deferred,
     G::PrimitiveType::LineList, G::GraphicsProfile::Reach, G::GraphicsDeviceStatus::Normal,
     G::ClearOptions::Target, G::SpriteEffects::FlipHorizontally, G::VertexElementFormat::Vector2,
     F::DisplayOrientation::Default, I::GamePadType::GamePad, I::ButtonState::Pressed]
  end

  def self.ruby_type(clr_name)
    clr_name.split(".").reduce(Object) { |scope, segment| scope.const_get(segment, false) }
  end

  BATCH.each do |clr_name, flags, values|
    short = clr_name.split(".").last
    slug = short.gsub(/([a-z0-9])([A-Z])/, '\1_\2').downcase

    define_method("test_#{slug}_matches_the_pinned_reference_contract") do
      pinned = REFERENCE.fetch(clr_name)
      assert_equal "enum", pinned.fetch("kind")
      assert_equal "System.Int32", pinned.fetch("underlyingType")
      assert_equal flags, pinned.fetch("flags")
      storage = pinned.fetch("members").select { |member| member.fetch("name") == "value__" }
      assert_equal 1, storage.length
      assert_equal "System.Int32", storage.first.fetch("type")
      declared = pinned.fetch("members").reject { |member| member.fetch("name") == "value__" }
      assert_equal values, declared.to_h { |member| [member.fetch("name"), Integer(member.fetch("value"))] }
      assert declared.all? { |member| member.fetch("kind") == "field" && member.fetch("static") }
      assert declared.all? { |member| member.fetch("type") == clr_name }
      assert_equal values.length + 1, pinned.fetch("members").length
    end

    define_method("test_#{slug}_selected_surface_excludes_synthetic_storage") do
      selected = SIGNATURES.fetch(clr_name)
      assert_equal "enum", selected.fetch("kind")
      assert_equal flags, selected.fetch("flags")
      assert_equal "System.Int32", selected.fetch("underlyingType")
      assert_equal values, selected.fetch("members").to_h { |member| [member.fetch("name"), Integer(member.fetch("value"))] }
      assert_equal values.length, selected.fetch("members").length
      refute selected.fetch("members").any? { |member| member.fetch("name") == "value__" }
      assert_equal clr_name.split(".").join("::"), selected.fetch("rubyName")
    end

    define_method("test_#{slug}_exposes_exact_typed_frozen_canonical_values") do
      type = self.class.ruby_type(clr_name)
      assert_equal CNA::Runtime::EnumValue, type.superclass
      assert_instance_of Class, type
      assert_equal values.keys.sort, type.constants(false).map(&:to_s).sort
      refute_includes type.constants(false), :value__

      values.each do |name, raw|
        value = type.const_get(name, false)
        assert_instance_of type, value
        assert_predicate value, :frozen?
        assert_equal raw, value.value
        assert_equal raw, value.to_i
        assert_equal name, value.name
        assert_equal name, value.to_s
        assert_equal "#{type.name}::#{name}", value.inspect
        assert_same value, type.const_get(name, false)
        assert_same value, type.coerce(raw)
        assert_same value, type.coerce(value)
        assert_equal 0, value <=> value
      end

      assert_equal flags, type.instance_variable_get(:@enum_flags)
      expected_mask = flags ? values.values.reduce(0) { |mask, raw| mask | raw } : 0
      assert_equal expected_mask, type.instance_variable_get(:@enum_mask)
      assert_raises(NoMethodError) { type.new(type, "Forged", 0) }
    end

    define_method("test_#{slug}_rejects_non_integer_and_cross_enum_input") do
      type = self.class.ruby_type(clr_name)
      sample = type.const_get(values.keys.first, false)

      [nil, true, false, 1.0, "1", :None, Object.new, [0], 0..1].each do |bad|
        assert_raises(TypeError) { type.coerce(bad) }
      end

      FOREIGN.call.reject { |value| value.instance_of?(type) }.each do |foreign|
        assert_raises(TypeError) { type.coerce(foreign) }
        refute_equal sample, foreign
        refute_operator sample, :eql?, foreign
        assert_nil sample <=> foreign
        assert_raises(TypeError) { sample | foreign }
        assert_raises(TypeError) { sample & foreign }
      end
    end

    if flags
      define_method("test_#{slug}_composes_only_declared_bits") do
        type = self.class.ruby_type(clr_name)
        mask = values.values.reduce(0) { |accumulator, raw| accumulator | raw }
        declared = values.keys.map { |name| type.const_get(name, false) }

        declared.combination(2).each do |left, right|
          combined = left | right
          assert_instance_of type, combined
          assert_predicate combined, :frozen?
          assert_equal left.to_i | right.to_i, combined.to_i
          assert_same combined, type.coerce(left.to_i | right.to_i)
          intersection = left & right
          assert_instance_of type, intersection
          assert_equal left.to_i & right.to_i, intersection.to_i
        end

        (0..mask).select { |raw| (raw & ~mask).zero? }.each do |raw|
          assert_instance_of type, type.coerce(raw)
          assert_equal raw, type.coerce(raw).to_i
        end
        [mask | (mask + 1), ~mask & 0xFFFF, -1].reject { |raw| (raw & ~mask).zero? }.each do |raw|
          assert_raises(RangeError) { type.coerce(raw) }
        end
      end
    else
      define_method("test_#{slug}_rejects_flags_composition_and_undefined_raw_values") do
        type = self.class.ruby_type(clr_name)
        declared = values.keys.map { |name| type.const_get(name, false) }

        declared.each do |left|
          declared.each do |right|
            assert_raises(TypeError) { left | right }
            assert_raises(TypeError) { left & right }
          end
        end

        assert_equal 0, type.instance_variable_get(:@enum_mask)
        refute_respond_to type, :from_flags_value

        undefined = ([-1, values.values.max + 1, 12_345, 2_147_483_647, -2_147_483_648] +
                     (0..values.values.max).to_a).reject { |raw| values.value?(raw) }
        undefined.uniq.each { |raw| assert_raises(RangeError) { type.coerce(raw) } }
      end
    end

    define_method("test_#{slug}_adds_no_invented_identity_or_helper_api") do
      type = self.class.ruby_type(clr_name)
      sample = type.const_get(values.keys.first, false)

      # value__ can never be a Ruby constant name; the exact constant set is pinned above.
      %i[Parse TryParse FromInt32 GetValues GetNames All Default Unknown Count]
        .reject { |name| values.key?(name.to_s) }
        .each { |name| refute type.const_defined?(name, false), "#{clr_name}::#{name}" }
      %i[Parse TryParse FromInt32 GetValues GetNames Values Names]
        .each { |name| refute_respond_to type, name }
      %i[ToString HasFlag CompareTo GetHashCode Equals ToNative NativeValue GlEnum
         D3DValue to_native native_value].each { |name| refute_respond_to sample, name }

      # Language-only projections are not XNA identities and stay the established four.
      assert_equal %i[value name to_s inspect to_i hash eql? == <=> | &].sort.uniq,
                   (CNA::Runtime::EnumValue.public_instance_methods(false) +
                    CNA::Runtime::EnumValue.instance_methods(false)).sort.uniq
      assert_empty type.public_instance_methods(false)
      assert_empty type.protected_instance_methods(false)
    end

    define_method("test_#{slug}_is_declared_only_in_its_own_namespace") do
      type = self.class.ruby_type(clr_name)
      segments = clr_name.split(".")
      owner = segments[0..-2].reduce(Object) { |scope, segment| scope.const_get(segment, false) }
      short_name = segments.last
      assert_same type, owner.const_get(short_name, false)

      [F, G, I, A, M, F::Graphics::GraphicsDevice].each do |scope|
        next if scope.equal?(owner)

        refute scope.const_defined?(short_name, false), "#{scope}::#{short_name}"
      end
    end
  end

  def test_batch_contains_only_dependency_complete_pure_managed_enums
    strict = JSON.parse(Pathname(__dir__).join("..", "docs", "generated", "api-compat-report.json").read)
    BATCH.each do |clr_name, _flags, values|
      assert_includes strict.fetch("completeTypeNames"), clr_name
      assert_equal 0, strict.fetch("localDiagnostics").fetch(clr_name), clr_name
      refute_includes strict.fetch("missingTypeNames"), clr_name
      refute strict.fetch("partialTypes").key?(clr_name)
      assert_equal values.length, SIGNATURES.fetch(clr_name).fetch("members").length
    end
    assert_equal BATCH.length, BATCH.map(&:first).uniq.length
    assert_equal 24, FOUNDATION16_BATCH.length
    assert_equal 109, FOUNDATION16_BATCH.sum { |_clr, _flags, values| values.length }
    assert_equal 2, FOUNDATION17_TOUCH.length
    assert_equal 15, FOUNDATION17_TOUCH.sum { |_clr, _flags, values| values.length }
    assert_equal 26, BATCH.length
  end

  def test_batch_adds_no_native_binding_constant_or_callback
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:constants), CNA::Native::Manifest::CONSTANTS.length
    # Fragments must stay specific: CNA_SURFACE_FORMAT_COLOR legitimately contains "FACE".
    %w[CUBE_MAP CUBEMAP CUBE_FACE BUFFER_USAGE AUDIO_CHANNEL STOP_OPTION SOUND_STATE MEDIA
       BLEND STENCIL COMPARE TEXTURE_FILTER ADDRESS_MODE CULL FILL_MODE PRESENT_INTERVAL
       RENDER_TARGET_USAGE SET_DATA COLOR_WRITE EFFECT_PARAMETER INDEX_ELEMENT].each do |fragment|
      refute CNA::Native::Manifest::CONSTANTS.keys.any? { |name| name.include?(fragment) }, fragment
    end
    # `sound_` and `audio_` left this list when the audio cluster was built, which is a statement
    # about that milestone rather than about this one: what this one claims is that *its* 24 enums
    # bound nothing, and every other fragment still proves it.
    # `MICROPHONE` and `microphone_` left these lists when `Microphone` was built, and for the same
    # reason `sound_`, `audio_` and `buffer_` left them: the three CNA_MICROPHONE_STATE_* identities
    # and the sixteen cna_microphone_* routes belong to that milestone, not to this batch's 24
    # enums. `MicrophoneState`, the enum this batch really did select, still takes its values from
    # its own IL and is asserted below to be a pure-managed projection.
    # `buffer_` left this list when the streaming audio instance was built; the fragments that
    # remain still prove the 24 enums of *this* batch bound nothing.
    # `media_` left this list when Media.MediaSource bound its four measurement routes, for the
    # same reason `microphone_`, `sound_`, `audio_` and `buffer_` left it: those routes belong to
    # the milestones that bound them, not to this batch's 24 enums.
    # `stencil_` left this list when the GraphicsDeviceManager preferences milestone bound
    # `set_preferred_depth_stencil_format`, for the same reason every other fragment left it: that
    # route belongs to the milestone that bound it, not to this batch's 24 enums.
    %w[cube_ blend_ sampler_
       render_target_ index_buffer_ vertex_buffer_].each do |fragment|
      refute CNA::Native::Manifest::FUNCTIONS.any? { |entry| entry.symbol.include?(fragment) }, fragment
    end
  end

  def test_batch_implies_no_renderer_device_audio_media_or_touch_surface
    %i[RenderTarget2D RenderTargetCube TextureCube Texture3D VertexBuffer IndexBuffer
       DynamicVertexBuffer DynamicIndexBuffer VertexDeclaration BlendState DepthStencilState
       RasterizerState SamplerState SamplerStateCollection Effect BasicEffect
       EffectParameter EffectTechnique GraphicsAdapter
       OcclusionQuery].each do |name|
      refute G.const_defined?(name, false), "Graphics::#{name}"
    end
    # `SoundEffect` and `SoundEffectInstance` exist now; what this milestone claimed, and still
    # claims, is that **it** built neither. The list narrows to the audio types nothing here has
    # built rather than being loosened.
    # The whole Audio namespace is projected now; what this batch claimed is that **it** built
    # none of it, which `test_batch_adds_no_native_binding_constant_or_callback` measures directly.
    %i[AudioChannels AudioStopOptions MicrophoneState SoundState]
      .each { |name| assert A.const_defined?(name, false), "Audio::#{name}" }
    # VisualizationData arrived in Foundation 51 from its own IL: a constructible holder whose
    # filler, MediaPlayer.GetVisualizationData, is still one of the names below.
    %i[MediaPlayer MediaLibrary Song Album Artist VideoPlayer Playlist
       Picture PictureAlbum].each do |name|
      refute M.const_defined?(name, false), "Media::#{name}"
    end
    # Keyboard, KeyboardState and Keys predate these batches. Input::Touch was opened by
    # Foundation 17 and extended by Foundation 23 with the two publicly constructible value types;
    # nothing that reads a touch device is there.
    # Foundation 31 added TouchCollection, whose IL reads nothing.
    assert_equal %i[GestureSample GestureType TouchCollection TouchLocation TouchLocationState
                    TouchPanel TouchPanelCapabilities],
                 T.constants(false).sort
    %i[TouchPanel TouchCollection TouchLocation GestureSample TouchLocationState GestureType]
      .each { |name| refute I.const_defined?(name, false), "Input::#{name}" }
    # Foundation 32 added TouchPanel, whose IL reads no device on this profile.
    refute I.const_defined?(:TouchPanel, false), "Input::TouchPanel"
    assert_equal %i[IsDisposed Viewport Clear Textures VertexTextures].sort,
                 G::GraphicsDevice.public_instance_methods(false).sort
  end

  def test_batch_namespaces_expose_only_the_selected_enum_types
    {A => %i[AudioChannels AudioStopOptions MicrophoneState SoundState],
     M => %i[MediaSourceType MediaState VideoSoundtrackType],
     T => %i[GestureType TouchLocationState]}.each do |namespace, expected|
      declared = namespace.constants(false).sort
      selected = expected.select { |name| BATCH.any? { |clr, _, _| clr.end_with?(".#{name}") } }.sort
      # Input::Touch also carries the TouchPanelCapabilities struct and the Foundation 23 value
      # types TouchLocation and GestureSample; Audio carries the three Foundation 22 exception
      # types. None of those is an enum.
      value_types = %i[TouchPanelCapabilities TouchLocation GestureSample TouchCollection
                       TouchPanel AudioListener AudioEmitter RendererDetail VisualizationData Video
                       SoundEffect SoundEffectInstance DynamicSoundEffectInstance Microphone
                       AudioEngine AudioCategory WaveBank SoundBank Cue MediaSource]
      extras = declared & value_types
      extras += declared.grep(/Exception\z/)
      assert_equal (selected + extras).uniq.sort, declared, namespace.name
      declared.each do |name|
        next if value_types.include?(name)
        next if name.to_s.end_with?("Exception")

        assert_operator namespace.const_get(name, false), :<, CNA::Runtime::EnumValue
      end
      declared.grep(/Exception\z/).each do |name|
        assert_operator namespace.const_get(name, false), :<, StandardError, name
      end
    end
  end

  def test_isolated_require_projects_the_batch_without_loading_the_native_library
    library = File.expand_path("../lib", __dir__)
    table = BATCH.to_h { |clr_name, flags, values| [clr_name, [flags, values]] }
    script = <<~'RUBY'
      require "json"
      require "microsoft/xna/framework/audio"
      require "microsoft/xna/framework/graphics"
      require "microsoft/xna/framework/input/touch"
      require "microsoft/xna/framework/media"
      JSON.parse(ARGV.fetch(0)).each do |clr_name, (flags, values)|
        type = clr_name.split(".").reduce(Object) { |scope, segment| scope.const_get(segment, false) }
        abort "#{clr_name} constants" unless type.constants(false).map(&:to_s).sort == values.keys.sort
        values.each do |name, raw|
          abort "#{clr_name}::#{name}" unless type.const_get(name, false).to_i == raw
        end
        abort "#{clr_name} flags" unless type.instance_variable_get(:@enum_flags) == flags
      end
      abort "native library loaded" if CNA::Native.instance_variable_defined?(:@library)
    RUBY
    environment = {"CNA_NATIVE_LIBRARY" => nil, "RUBYLIB" => ENV["RUBYLIB"], "RUBYOPT" => nil}
    ruby = ENV.fetch("RUBY_EXECUTABLE", RbConfig.ruby)
    output, error, status = Open3.capture3(environment, ruby, "-I#{library}", "-e", script, JSON.generate(table))
    assert status.success?, "#{output}#{error}"
  end
end
