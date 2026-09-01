# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require_relative "../lib/microsoft/xna/framework/graphics"
require_relative "../lib/microsoft/xna/framework/input"

class DepthFormatTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = F::Graphics
  I = F::Input
  FORMAT = G::DepthFormat

  def test_graphics_require_exposes_exact_typed_frozen_non_flags_constants
    expected = {None: 0, Depth16: 1, Depth24: 2, Depth24Stencil8: 3}

    assert_same FORMAT, G.const_get(:DepthFormat, false)
    refute F.const_defined?(:DepthFormat, false)
    refute G::GraphicsDevice.const_defined?(:DepthFormat, false)
    assert_equal CNA::Runtime::EnumValue, FORMAT.superclass
    assert_equal expected.keys.sort, FORMAT.constants(false).sort
    expected.each do |name, raw|
      value = FORMAT.const_get(name, false)
      assert_instance_of FORMAT, value
      assert_predicate value, :frozen?
      assert_equal raw, value.value
      assert_equal raw, value.to_i
      assert_equal name.to_s, value.name
      assert_same value, FORMAT.const_get(name, false)
    end
    assert_equal false, FORMAT.instance_variable_get(:@enum_flags)
    assert_equal 0, FORMAT.instance_variable_get(:@enum_mask)
    refute_includes FORMAT.constants(false), :value__
  end

  def test_no_alias_or_invented_depth_identity_is_added
    %i[Default Depth32 Stencil8 Depth24Stencil Depth15Stencil1 D16 D24 D24S8 Unknown].each do |name|
      refute FORMAT.const_defined?(name, false), name.to_s
    end
  end

  def test_declared_values_are_canonical_under_existing_ordinary_enum_policy
    assert_same FORMAT::None, FORMAT.coerce(0)
    assert_same FORMAT::Depth16, FORMAT.coerce(1)
    assert_same FORMAT::Depth24, FORMAT.coerce(2)
    assert_same FORMAT::Depth24Stencil8, FORMAT.coerce(3)

    [FORMAT::None, FORMAT::Depth16, FORMAT::Depth24, FORMAT::Depth24Stencil8].each do |value|
      assert_same value, FORMAT.coerce(value)
    end

    assert_equal "None", FORMAT::None.to_s
    assert_equal "Depth16", FORMAT::Depth16.to_s
    assert_equal "Depth24Stencil8", FORMAT::Depth24Stencil8.to_s
    assert_equal "Microsoft::Xna::Framework::Graphics::DepthFormat::Depth24",
                 FORMAT::Depth24.inspect
    assert_equal 3, FORMAT::Depth24Stencil8.to_i
  end

  def test_undefined_raw_values_and_non_integer_values_are_rejected
    [4, -1, 12_345, 2_147_483_647].each { |raw| assert_raises(RangeError) { FORMAT.coerce(raw) } }
    [nil, true, false, 1.0, "1", :Depth16, Object.new].each do |value|
      assert_raises(TypeError) { FORMAT.coerce(value) }
    end
  end

  def test_non_flags_operators_reject_and_depth24stencil8_is_not_a_flags_composition
    assert_raises(TypeError) { FORMAT::Depth16 | FORMAT::Depth24 }
    assert_raises(TypeError) { FORMAT::Depth24Stencil8 & FORMAT::Depth16 }
    assert_raises(TypeError) { FORMAT::None | FORMAT::Depth24Stencil8 }
    assert_raises(TypeError) { FORMAT::Depth24 & FORMAT::Depth24 }

    # 1 | 2 == 3 numerically, but Depth24Stencil8 is one ordinary enum literal.
    assert_equal 3, FORMAT::Depth16.to_i | FORMAT::Depth24.to_i
    assert_equal false, FORMAT.instance_variable_get(:@enum_flags)
    assert_equal 0, FORMAT.instance_variable_get(:@enum_mask)
    refute_respond_to FORMAT, :from_flags_value
    assert_raises(RangeError) { FORMAT.coerce(4) }
  end

  def test_cross_type_values_are_not_accepted_or_equal
    foreign_values = [
      G::SurfaceFormat::Color,
      G::GraphicsProfile::Reach,
      G::GraphicsDeviceStatus::Normal,
      G::ClearOptions::DepthBuffer,
      F::DisplayOrientation::Default,
      G::VertexElementFormat::Vector2,
      I::GamePadType::GamePad
    ]

    foreign_values.each do |value|
      assert_raises(TypeError) { FORMAT.coerce(value) }
      refute_equal FORMAT::Depth24, value
      assert_nil FORMAT::Depth24 <=> value
      assert_raises(TypeError) { FORMAT::Depth24 | value }
      assert_raises(TypeError) { FORMAT::Depth24 & value }
    end

    refute_equal G::ClearOptions::DepthBuffer, FORMAT::Depth24
    refute_equal FORMAT::Depth16, G::SurfaceFormat::Bgr565
  end

  def test_language_support_adds_no_xna_identity_or_depth_functionality
    assert_respond_to FORMAT::Depth24, :to_s
    assert_respond_to FORMAT::Depth24, :inspect
    assert_respond_to FORMAT::Depth24, :to_i
    %i[ToString HasFlag HasStencil has_stencil? DepthBits depth_bits StencilBits stencil_bits
       IsDepthOnly IsDepthStencil NativeFormat Parse FromInt32 depth24? stencil?].each do |name|
      refute_respond_to FORMAT::Depth24, name
    end
    %i[Parse FromInt32 TryParse GetValues].each { |name| refute_respond_to FORMAT, name }
  end

  def test_no_presentation_or_state_surface_is_implemented
    # `GraphicsDeviceManager.PreferredDepthStencilFormat` exists now, and its default really is this
    # enum's `Depth24` -- `ldc.i4.2` in the manager's constructor, which is the one place the IL
    # names a member of this enum. What this milestone claimed, and still claims, is that **it**
    # added no manager property and no state object; the enum alone implies neither.
    assert_equal G::DepthFormat::Depth24, F::GraphicsDeviceManager.new(NullGame.new).PreferredDepthStencilFormat
    refute_includes G::GraphicsDevice.public_instance_methods(false), :DepthStencilState
    # The two render targets left this list when they were built: they are the first types in this
    # binding to carry a `DepthStencilFormat`, which is this enum's first real consumer, and they
    # still add no manager property and no state object. This batch built neither of them.
    %i[GraphicsAdapter DepthFormatConverter].each do |name|
      refute G.const_defined?(name, false), name.to_s
    end
    assert G::RenderTarget2D.public_method_defined?(:DepthStencilFormat),
           "the render targets are this enum's first real consumer"

    assert_equal 1, G::GraphicsDevice.instance_method(:Clear).arity
    refute CNA::Native::Manifest::CONSTANTS.keys.any? { |name| name.include?("DEPTH_FORMAT") }
    # `DepthStencilState` was in that list until the four state objects were built. It is a managed
    # value holder with no device in it, so the claim this test really makes -- that the enum
    # implied no *device* surface -- is unchanged, and the two constants it named are still absent
    # from the device half of the manifest.
    assert G.const_defined?(:DepthStencilState, false)
    assert_nil G::DepthStencilState.new.GraphicsDevice
    refute CNA::Native::Manifest::CONSTANTS.keys.any? { |name| name.start_with?("CNA_DEPTH_STENCIL_FORMAT") }
  end

  class NullGame < Microsoft::Xna::Framework::Game; end

  def test_isolated_graphics_require_does_not_load_cna_native_library
    library = File.expand_path("../lib", __dir__)
    script = <<~'RUBY'
      require "microsoft/xna/framework/graphics"
      format = Microsoft::Xna::Framework::Graphics::DepthFormat
      abort "wrong values" unless format.constants(false).sort == %i[Depth16 Depth24 Depth24Stencil8 None]
      abort "wrong Depth24Stencil8" unless format::Depth24Stencil8.to_i == 3
      abort "flags leaked" if format.instance_variable_get(:@enum_flags)
      abort "native library loaded" if CNA::Native.instance_variable_defined?(:@library)
    RUBY
    environment = {"CNA_NATIVE_LIBRARY" => nil, "RUBYLIB" => ENV["RUBYLIB"], "RUBYOPT" => nil}
    ruby = ENV.fetch("RUBY_EXECUTABLE", RbConfig.ruby)
    output, error, status = Open3.capture3(environment, ruby, "-I#{library}", "-e", script)
    assert status.success?, "#{output}#{error}"
  end
end
