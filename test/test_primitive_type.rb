# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require_relative "../lib/microsoft/xna/framework/graphics"
require_relative "../lib/microsoft/xna/framework/input"

class PrimitiveTypeTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = F::Graphics
  I = F::Input
  TOPOLOGY = G::PrimitiveType

  def test_graphics_require_exposes_exact_typed_frozen_non_flags_constants
    expected = {TriangleList: 0, TriangleStrip: 1, LineList: 2, LineStrip: 3}

    assert_same TOPOLOGY, G.const_get(:PrimitiveType, false)
    refute F.const_defined?(:PrimitiveType, false)
    refute G::GraphicsDevice.const_defined?(:PrimitiveType, false)
    assert_equal CNA::Runtime::EnumValue, TOPOLOGY.superclass
    assert_equal expected.keys.sort, TOPOLOGY.constants(false).sort
    expected.each do |name, raw|
      value = TOPOLOGY.const_get(name, false)
      assert_instance_of TOPOLOGY, value
      assert_predicate value, :frozen?
      assert_equal raw, value.value
      assert_equal raw, value.to_i
      assert_equal name.to_s, value.name
      assert_same value, TOPOLOGY.const_get(name, false)
    end
    assert_equal false, TOPOLOGY.instance_variable_get(:@enum_flags)
    assert_equal 0, TOPOLOGY.instance_variable_get(:@enum_mask)
    refute_includes TOPOLOGY.constants(false), :value__
  end

  def test_xna40_raw_values_are_used_rather_than_the_xna31_direct3d9_ordering
    # XNA 3.1 declared PointList=0, LineList=1, LineStrip=2, TriangleList=3,
    # TriangleStrip=4, TriangleFan=5. XNA 4.0 renumbered the surviving four and
    # dropped the other two, so the Direct3D 9 ordering must not be assumed.
    assert_equal 0, TOPOLOGY::TriangleList.to_i
    assert_equal 1, TOPOLOGY::TriangleStrip.to_i
    assert_equal 2, TOPOLOGY::LineList.to_i
    assert_equal 3, TOPOLOGY::LineStrip.to_i

    refute_equal 1, TOPOLOGY::LineList.to_i
    refute_equal 2, TOPOLOGY::LineStrip.to_i
    refute_equal 3, TOPOLOGY::TriangleList.to_i
    refute_equal 4, TOPOLOGY::TriangleStrip.to_i
    assert_same TOPOLOGY::TriangleList, TOPOLOGY.coerce(0)
    refute_same TOPOLOGY::LineList, TOPOLOGY.coerce(1)
  end

  def test_no_alias_or_invented_topology_identity_is_added
    %i[PointList TriangleFan LineLoop Patches PointListStrip Default Unknown None
       Triangles Lines TriangleListAdjacency LineListAdjacency QuadList].each do |name|
      refute TOPOLOGY.const_defined?(name, false), name.to_s
    end
  end

  def test_declared_values_are_canonical_under_existing_ordinary_enum_policy
    assert_same TOPOLOGY::TriangleList, TOPOLOGY.coerce(0)
    assert_same TOPOLOGY::TriangleStrip, TOPOLOGY.coerce(1)
    assert_same TOPOLOGY::LineList, TOPOLOGY.coerce(2)
    assert_same TOPOLOGY::LineStrip, TOPOLOGY.coerce(3)

    [TOPOLOGY::TriangleList, TOPOLOGY::TriangleStrip, TOPOLOGY::LineList, TOPOLOGY::LineStrip].each do |value|
      assert_same value, TOPOLOGY.coerce(value)
    end

    assert_equal "TriangleList", TOPOLOGY::TriangleList.to_s
    assert_equal "TriangleStrip", TOPOLOGY::TriangleStrip.to_s
    assert_equal "LineList", TOPOLOGY::LineList.to_s
    assert_equal "LineStrip", TOPOLOGY::LineStrip.to_s
    assert_equal "Microsoft::Xna::Framework::Graphics::PrimitiveType::LineList",
                 TOPOLOGY::LineList.inspect
    assert_equal 3, TOPOLOGY::LineStrip.to_i
  end

  def test_undefined_raw_values_and_non_integer_values_are_rejected
    [4, 5, -1, 12_345, 2_147_483_647].each { |raw| assert_raises(RangeError) { TOPOLOGY.coerce(raw) } }
    [nil, true, false, 1.0, "1", :LineList, Object.new].each do |value|
      assert_raises(TypeError) { TOPOLOGY.coerce(value) }
    end
  end

  def test_non_flags_operators_are_rejected
    assert_raises(TypeError) { TOPOLOGY::TriangleList | TOPOLOGY::TriangleStrip }
    assert_raises(TypeError) { TOPOLOGY::LineList & TOPOLOGY::LineStrip }
    assert_raises(TypeError) { TOPOLOGY::TriangleStrip | TOPOLOGY::LineList }
    assert_raises(TypeError) { TOPOLOGY::LineStrip & TOPOLOGY::LineStrip }

    # 1 | 2 == 3 numerically, but LineStrip is one ordinary enum literal.
    assert_equal 3, TOPOLOGY::TriangleStrip.to_i | TOPOLOGY::LineList.to_i
    assert_equal false, TOPOLOGY.instance_variable_get(:@enum_flags)
    assert_equal 0, TOPOLOGY.instance_variable_get(:@enum_mask)
    refute_respond_to TOPOLOGY, :from_flags_value
    assert_raises(RangeError) { TOPOLOGY.coerce(4) }
  end

  def test_cross_type_values_are_not_accepted_or_equal
    foreign_values = [
      G::DepthFormat::Depth24,
      G::SurfaceFormat::Color,
      G::SpriteSortMode::Deferred,
      G::GraphicsProfile::Reach,
      G::GraphicsDeviceStatus::Normal,
      G::ClearOptions::Target,
      F::DisplayOrientation::Default,
      G::VertexElementFormat::Vector2,
      I::GamePadType::GamePad
    ]

    foreign_values.each do |value|
      assert_raises(TypeError) { TOPOLOGY.coerce(value) }
      refute_equal TOPOLOGY::LineList, value
      assert_nil TOPOLOGY::LineList <=> value
      assert_raises(TypeError) { TOPOLOGY::LineList | value }
      assert_raises(TypeError) { TOPOLOGY::LineList & value }
    end

    # Every raw value 0..3 collides with DepthFormat and SurfaceFormat.
    refute_equal G::DepthFormat::None, TOPOLOGY::TriangleList
    refute_equal G::SurfaceFormat::Bgr565, TOPOLOGY::TriangleStrip
    refute_equal G::SpriteSortMode::Texture, TOPOLOGY::LineList
    refute_equal G::DepthFormat::Depth24Stencil8, TOPOLOGY::LineStrip
  end

  def test_language_support_adds_no_xna_identity_or_topology_functionality
    assert_respond_to TOPOLOGY::LineList, :to_s
    assert_respond_to TOPOLOGY::LineList, :inspect
    assert_respond_to TOPOLOGY::LineList, :to_i
    %i[ToString HasFlag VertexCount vertex_count PrimitiveCount primitive_count
       GetElementCount ElementCount IndexCount NativeTopology native_topology
       ToTopology GlEnum D3DPrimitiveType Parse FromInt32 triangle? line? strip?
       IsStrip IsList].each do |name|
      refute_respond_to TOPOLOGY::LineList, name
    end
    %i[Parse FromInt32 TryParse GetValues VertexCount PrimitiveCount].each do |name|
      refute_respond_to TOPOLOGY, name
    end
  end

  def test_no_graphics_device_draw_member_is_implemented
    %i[DrawPrimitives DrawIndexedPrimitives DrawInstancedPrimitives
       DrawUserPrimitives DrawUserIndexedPrimitives].each do |name|
      refute G::GraphicsDevice.public_method_defined?(name), name.to_s
      refute G::GraphicsDevice.private_method_defined?(name), name.to_s
      refute G::GraphicsDevice.protected_method_defined?(name), name.to_s
    end
    assert_equal %i[IsDisposed Viewport Clear Textures VertexTextures SamplerStates VertexSamplerStates].sort,
                 G::GraphicsDevice.public_instance_methods(false).sort
  end

  def test_no_vertex_buffer_index_buffer_or_renderer_topology_surface_is_implemented
    # `RasterizerState` left this list when the four state objects were built: it is a managed
    # value holder that holds no buffer and draws nothing, so the claim is unchanged.
    # `VertexDeclaration` and `IVertexType` left this list when they were built. Neither holds a
    # buffer nor draws anything, so what this test claims is unchanged.
    # The nine `Effect` types left this list when the cluster was built; what this milestone
    # claimed, and still claims, is that **it** built none of them.
    # The five buffer types left this list when they were built; what this milestone claimed,
    # and still claims, is that **it** built none of them.
    %i[BasicEffect PrimitiveTypeConverter].each do |name|
      refute G.const_defined?(name, false), name.to_s
    end
    %i[SetVertexBuffer Indices DrawUserPrimitives].each do |name|
      refute G::GraphicsDevice.public_method_defined?(name), name.to_s
    end
    refute CNA::Native::Manifest::CONSTANTS.keys.any? { |name| name.include?("PRIMITIVE") }
    refute CNA::Native::Manifest::CONSTANTS.keys.any? { |name| name.include?("TOPOLOGY") }
    refute CNA::Native::Manifest::FUNCTIONS.any? { |entry| entry.symbol.include?("primitive") }
    # `cna_sprite_batch_draw_string` left this check when DrawString was built: it draws text
    # through a SpriteBatch interval, not a primitive topology, and no primitive or topology
    # constant or route exists at all.
    refute CNA::Native::Manifest::FUNCTIONS.any? { |entry| entry.symbol.include?("draw_primitive") }
    refute CNA::Native::Manifest::FUNCTIONS.any? { |entry| entry.symbol.include?("draw_user") }
  end

  def test_isolated_graphics_require_does_not_load_cna_native_library
    library = File.expand_path("../lib", __dir__)
    script = <<~'RUBY'
      require "microsoft/xna/framework/graphics"
      topology = Microsoft::Xna::Framework::Graphics::PrimitiveType
      abort "wrong values" unless topology.constants(false).sort == %i[LineList LineStrip TriangleList TriangleStrip]
      abort "wrong TriangleList" unless topology::TriangleList.to_i == 0
      abort "wrong LineStrip" unless topology::LineStrip.to_i == 3
      abort "flags leaked" if topology.instance_variable_get(:@enum_flags)
      abort "draw leaked" if Microsoft::Xna::Framework::Graphics::GraphicsDevice.public_method_defined?(:DrawPrimitives)
      abort "native library loaded" if CNA::Native.instance_variable_defined?(:@library)
    RUBY
    environment = {"CNA_NATIVE_LIBRARY" => nil, "RUBYLIB" => ENV["RUBYLIB"], "RUBYOPT" => nil}
    ruby = ENV.fetch("RUBY_EXECUTABLE", RbConfig.ruby)
    output, error, status = Open3.capture3(environment, ruby, "-I#{library}", "-e", script)
    assert status.success?, "#{output}#{error}"
  end
end
