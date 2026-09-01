# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# `Graphics.Texture3D` and `Graphics.TextureCube` — the two texture types `EffectParameter`'s
# `GetValueTexture3D` and `GetValueTextureCube` return, and the reason the Effect cluster could not
# be strictly complete without them.
#
# Both are the first types in this binding whose *behaviour* depends on which qualified artifact is
# loaded rather than only on whether one is: `HEADLESS` refuses volume creation outright and refuses
# to store a cube face, `OPENGL33` round-trips both exactly. So the managed contract is asserted
# unconditionally and the storage is asserted against what the renderer itself was measured to do.
class TextureVolumeTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  VOLUME = "Microsoft.Xna.Framework.Graphics.Texture3D"
  CUBE = "Microsoft.Xna.Framework.Graphics.TextureCube"

  # ------------------------------------------------------------------------------- the contract

  def test_both_types_are_complete_and_derive_from_texture
    [VOLUME, CUBE].each do |name|
      assert_includes STRICT.fetch("completeTypeNames"), name
      assert_empty ReviewedScoreboard.partial_remainder(STRICT, name)
      assert_equal "Microsoft.Xna.Framework.Graphics.Texture", REFERENCE.fetch(name).fetch("baseType")
      refute REFERENCE.fetch(name).fetch("sealed"), "#{name} is not sealed; RenderTarget derives from it"
    end
    assert_equal G::Texture, G::Texture3D.superclass
    assert_equal G::Texture, G::TextureCube.superclass
  end

  # Both declare a **public** constructor, unlike `Texture` and `GraphicsResource`, whose are
  # `assembly` and whose `new` stays private.
  def test_both_constructors_are_public_and_the_bases_stay_private
    assert_equal 1, REFERENCE.fetch(VOLUME).fetch("members").count { |m| m.fetch("kind") == "constructor" }
    assert_equal 1, REFERENCE.fetch(CUBE).fetch("members").count { |m| m.fetch("kind") == "constructor" }
    assert G::Texture3D.respond_to?(:new)
    assert G::TextureCube.respond_to?(:new)
    refute G::Texture.respond_to?(:new)
  end

  def test_the_two_types_grew_the_reviewed_native_surface_by_ten_routes
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:layouts), CNA::Native::Layouts::STRUCTURES.length
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    %w[create set_data get_data get_info destroy].each do |suffix|
      assert_includes symbols, "cna_texture3d_#{suffix}"
      assert_includes symbols, "cna_texturecube_#{suffix}"
    end
    # Neither of the two routes with no XNA identity here is bound.
    refute_includes symbols, "cna_texture3d_set_data_bytes"
    refute_includes symbols, "cna_texturecube_create_from_dds_memory"
  end

  # ------------------------------------------------------------------------------ live behaviour

  class TextureGame < F::Game
    attr_reader :result

    def initialize(&body)
      @body = body
      super()
      F::GraphicsDeviceManager.new(self)
    end

    def Draw(_time)
      @result = @body.call(self.GraphicsDevice)
    ensure
      self.Exit
    end
  end

  def with_device
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = TextureGame.new { |device| yield device }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  def error_of
    yield
    :ok
  rescue StandardError => error
    [error.class, error.message]
  end

  # ------------------------------------------------------------------------------------ Texture3D

  def test_the_volume_constructors_managed_refusals_are_xnas_own
    values = with_device do |device|
      [error_of { G::Texture3D.new(nil, 1, 1, 1, false, G::SurfaceFormat::Color) },
       error_of { G::Texture3D.new("device", 1, 1, 1, false, G::SurfaceFormat::Color) },
       error_of { G::Texture3D.new(device, 0, 1, 1, false, G::SurfaceFormat::Color) },
       error_of { G::Texture3D.new(device, 1, 0, 1, false, G::SurfaceFormat::Color) },
       error_of { G::Texture3D.new(device, 1, 1, 0, false, G::SurfaceFormat::Color) },
       error_of { G::Texture3D.new(device, -1, 1, 1, false, G::SurfaceFormat::Color) },
       error_of { G::Texture3D.new(device, 1, 1, 1, 1, G::SurfaceFormat::Color) },
       error_of { G::Texture3D.new(device, 1, 1, 1, false, 0) }]
    end
    assert_equal ArgumentError, values[0].first, "a null device is CreateTexture's own first check"
    assert_equal TypeError, values[1].first
    # width, height and depth in that order, each ResourcesMustBeGreaterThanZeroSize.
    assert_equal [RangeError] * 4, values[2..5].map(&:first)
    assert_equal %w[width height depth width], values[2..5].map(&:last)
    assert_equal [TypeError] * 2, values[6..7].map(&:first)
  end

  # The dimensions and the level count come back from CNA rather than from the request, which is
  # what makes them a measurement of the created resource.
  def test_a_created_volume_reports_its_own_dimensions
    skip "this renderer has no volume storage" unless RendererEnvironment.volume_storage?

    values = with_device do |device|
      flat = G::Texture3D.new(device, 4, 2, 2, false, G::SurfaceFormat::Color)
      chained = G::Texture3D.new(device, 8, 8, 8, true, G::SurfaceFormat::Color)
      result = [[flat.Width, flat.Height, flat.Depth, flat.LevelCount, flat.Format.to_s],
                [chained.Width, chained.Height, chained.Depth, chained.LevelCount],
                flat.GraphicsDevice.equal?(device), flat.IsDisposed]
      flat.Dispose
      chained.Dispose
      result << flat.IsDisposed
    end
    assert_equal [4, 2, 2, 1, "Color"], values[0]
    assert_equal [8, 8, 8, 4], values[1], "mipMap true really allocates a chain, 8 -> 4 -> 2 -> 1"
    assert values[2], "the parent device is the one that created it"
    refute values[3]
    assert values[4]
  end

  def test_volume_voxels_round_trip_exactly
    skip "this renderer has no volume storage" unless RendererEnvironment.volume_storage?

    values = with_device do |device|
      texture = G::Texture3D.new(device, 4, 2, 2, false, G::SurfaceFormat::Color)
      written = Array.new(16) { |index| F::Color.new(index * 16, index, 255 - index * 16, 255) }
      texture.SetData(F::Color, written)
      whole = Array.new(16) { F::Color.new(0, 0, 0, 0) }
      texture.GetData(F::Color, whole)
      # The ten-argument form addresses one box: the second slice only.
      slice = Array.new(8) { F::Color.new(0, 0, 0, 0) }
      texture.GetData(F::Color, 0, 0, 0, 4, 2, 1, 2, slice, 0, 8)
      result = [whole == written, slice == written[8, 8]]
      texture.Dispose
      result
    end
    assert_equal [true, true], values
  end

  # `Texture3D.GetAndValidateBox` compares **unsigned**, so a negative coordinate wraps and is
  # refused by the same `left >= right` test rather than by a sign check of its own.
  def test_the_volume_box_refusals_are_the_ils_own
    skip "this renderer has no volume storage" unless RendererEnvironment.volume_storage?

    values = with_device do |device|
      texture = G::Texture3D.new(device, 4, 2, 2, false, G::SurfaceFormat::Color)
      data = Array.new(16) { F::Color.new(1, 2, 3, 4) }
      result = [
        error_of { texture.SetData(F::Color, 0, 0, 0, 5, 2, 0, 2, data, 0, 16) },   # right past width
        error_of { texture.SetData(F::Color, 0, 2, 0, 2, 2, 0, 2, data, 0, 16) },   # left == right
        error_of { texture.SetData(F::Color, 0, 0, 0, 4, 3, 0, 2, data, 0, 16) },   # bottom past height
        error_of { texture.SetData(F::Color, 0, 0, 0, 4, 2, 0, 3, data, 0, 16) },   # back past depth
        error_of { texture.SetData(F::Color, 0, -1, 0, 4, 2, 0, 2, data, 0, 16) },  # negative left
        error_of { texture.SetData(F::Color, 0, 0, 0, 4, 2, 0, 1, data, 0, 16) },   # total size
        error_of { texture.SetData(F::Color, []) },                                  # empty is null
        error_of { texture.SetData(F::Color, nil) }
      ]
      texture.Dispose
      result
    end
    assert_equal [ArgumentError] * 5, values[0..4].map(&:first)
    assert_equal %w[box box box box box], values[0..4].map(&:last)
    assert_equal [ArgumentError, "invalid total size"], values[5]
    assert_equal [ArgumentError, "data"], values[6], "an empty array is ArgumentNullException(data)"
    assert_equal [ArgumentError, "data"], values[7]
  end

  # ---------------------------------------------------------------------------------- TextureCube

  def test_the_cube_constructors_managed_refusals_are_xnas_own
    values = with_device do |device|
      [error_of { G::TextureCube.new(nil, 1, false, G::SurfaceFormat::Color) },
       error_of { G::TextureCube.new(device, 0, false, G::SurfaceFormat::Color) },
       error_of { G::TextureCube.new(device, -4, false, G::SurfaceFormat::Color) },
       error_of { G::TextureCube.new(device, 1, nil, G::SurfaceFormat::Color) }]
    end
    assert_equal ArgumentError, values[0].first
    assert_equal [[RangeError, "size"], [RangeError, "size"]], values[1..2]
    assert_equal TypeError, values[3].first
  end

  def test_a_created_cube_reports_its_own_size
    values = with_device do |device|
      flat = G::TextureCube.new(device, 4, false, G::SurfaceFormat::Color)
      chained = G::TextureCube.new(device, 8, true, G::SurfaceFormat::Color)
      result = [[flat.Size, flat.LevelCount, flat.Format.to_s], [chained.Size, chained.LevelCount]]
      flat.Dispose
      chained.Dispose
      result
    end
    assert_equal [4, 1, "Color"], values[0]
    assert_equal [8, 4], values[1]
  end

  def test_cube_face_texels_round_trip_exactly
    skip "this renderer stores no cube faces" unless RendererEnvironment.cube_face_storage?

    values = with_device do |device|
      texture = G::TextureCube.new(device, 2, false, G::SurfaceFormat::Color)
      faces = %i[PositiveX NegativeX PositiveY NegativeY PositiveZ NegativeZ]
      written = faces.each_with_index.to_h do |face, index|
        [face, Array.new(4) { |texel| F::Color.new(index * 40, texel * 60, 7, 255) }]
      end
      written.each { |face, pixels| texture.SetData(F::Color, G::CubeMapFace.const_get(face), pixels) }
      # Every face reads back its own pixels, which is what makes the face argument load-bearing.
      read = faces.to_h do |face|
        buffer = Array.new(4) { F::Color.new(0, 0, 0, 0) }
        texture.GetData(F::Color, G::CubeMapFace.const_get(face), buffer)
        [face, buffer]
      end
      # And a sub-rectangle addresses one texel of one face.
      corner = [F::Color.new(0, 0, 0, 0)]
      texture.GetData(F::Color, G::CubeMapFace::NegativeZ, 0, F::Rectangle.new(1, 1, 1, 1), corner, 0, 1)
      result = [read == written, corner.first == written.fetch(:NegativeZ)[3]]
      texture.Dispose
      result
    end
    assert_equal [true, true], values
  end

  def test_the_cube_rect_refusals_are_the_ils_own
    values = with_device do |device|
      texture = G::TextureCube.new(device, 2, false, G::SurfaceFormat::Color)
      data = Array.new(4) { F::Color.new(1, 2, 3, 4) }
      result = [
        error_of { texture.SetData(F::Color, G::CubeMapFace::PositiveX, 0, F::Rectangle.new(-1, 0, 2, 2), data, 0, 4) },
        error_of { texture.SetData(F::Color, G::CubeMapFace::PositiveX, 0, F::Rectangle.new(0, 0, 3, 2), data, 0, 4) },
        error_of { texture.SetData(F::Color, G::CubeMapFace::PositiveX, 0, F::Rectangle.new(0, 0, 0, 2), data, 0, 4) },
        error_of { texture.SetData(F::Color, G::CubeMapFace::PositiveX, 0, F::Rectangle.new(0, 0, 1, 1), data, 0, 4) },
        error_of { texture.SetData(F::Color, G::CubeMapFace::PositiveX, []) },
        error_of { texture.SetData(F::Color, 99, data) }
      ]
      texture.Dispose
      result
    end
    assert_equal [[ArgumentError, "rect"]] * 3, values[0..2]
    assert_equal [ArgumentError, "invalid total size"], values[3]
    assert_equal [ArgumentError, "data"], values[4]
    assert_equal RangeError, values[5].first, "CubeMapFace.coerce refuses an undefined face"
  end

  # --------------------------------------------------------------- the recorded native deviations

  # DEVIATION, recorded: XNA's `SetData<T>` takes any `T : struct` whose size divides the format's,
  # and CNA's volume and cube routes take `const CNA_Color*`. The managed validation still runs in
  # XNA's order -- an over-long array is refused before the element type is -- and the refusal is
  # `NotSupportedError`, the projection of the exception XNA itself raises for a request a profile
  # cannot carry.
  def test_a_non_color_element_type_is_refused_after_the_managed_validation
    values = with_device do |device|
      volume = G::Texture3D.new(device, 2, 1, 1, false, G::SurfaceFormat::Color) if RendererEnvironment.volume_storage?
      cube = G::TextureCube.new(device, 1, false, G::SurfaceFormat::Color)
      packed = [G::PackedVector::Bgra4444.new(1.0, 0.0, 0.0, 1.0)] * 4
      result = []
      if volume
        result << error_of { volume.SetData(G::PackedVector::Bgra4444, packed) }
        # The managed rule runs first: two elements of two bytes is not the volume's total size.
        result << error_of { volume.SetData(G::PackedVector::Bgra4444, packed[0, 2]) }
        volume.Dispose
      end
      # A 1x1 Color face is four bytes, so two `Bgra4444` elements pass the total-size rule and
      # reach the route's own refusal; three do not and are refused before it.
      result << error_of { cube.SetData(G::PackedVector::Bgra4444, G::CubeMapFace::PositiveX, packed[0, 2]) }
      result << error_of { cube.SetData(G::PackedVector::Bgra4444, G::CubeMapFace::PositiveX, packed[0, 3]) }
      cube.Dispose
      result
    end
    assert_equal CNA::Runtime::NotSupportedError, values[-2].first,
                 "the Color-only route refuses another element type"
    assert_equal [ArgumentError, "invalid total size"], values[-1],
                 "and XNA's own total-size rule is applied before it"
    if RendererEnvironment.volume_storage?
      assert_equal CNA::Runtime::NotSupportedError, values[0].first
      assert_equal [ArgumentError, "invalid total size"], values[1]
    end
  end

  # The measurement itself, stated so a reader can see which artifact produced which column.
  def test_the_storage_measurement_matches_the_renderer_report
    skip "CNA_NATIVE_LIBRARY not supplied" unless RendererEnvironment.available?

    report = JSON.parse(ROOT.join("docs", "generated", "renderer-native-report.json").read).fetch("runs")
    run = report[RendererEnvironment.renderer_name]
    skip "no recorded run for #{RendererEnvironment.renderer_name}" if run.nil?

    # `CNA_GRAPHICS_CAPABILITY_TEXTURE_3D` is capability 8, and the measurement agrees with it.
    assert_equal run.fetch("renderer").fetch("capabilities").fetch("8"), RendererEnvironment.volume_storage?
  end
end
