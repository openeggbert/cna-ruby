# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require "stringio"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `Texture2D.SetData` and `GetData` — pixel access, and the largest single derivation in the graphics
# half: six overloads that are all thin forwards into one 549-byte `CopyData`, whose validation lives
# in four helpers.
class Texture2DPixelsTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.Texture2D"

  # ------------------------------------------------------------------- the contract, from metadata

  # Three overloads each, generic over `T : struct`, which Ruby cannot dispatch on by parameter type
  # — so they collapse into one method dispatching on **arity**, with the type argument leading.
  def test_the_six_overloads_collapse_by_arity_with_the_type_argument_leading
    %w[SetData GetData].each do |name|
      overloads = REFERENCE.fetch(NAME).fetch("members").select { |m| m.fetch("name") == name }
      assert_equal 3, overloads.length, name
      assert(overloads.all? { |m| m.fetch("genericParameters").length == 1 }, "#{name} is generic")
      assert_equal [1, 3, 5].sort, overloads.map { |m| m.fetch("parameters").length }.sort
      assert G::Texture2D.public_method_defined?(name)
      assert_equal(-2, G::Texture2D.instance_method(name).arity, "#{name}(type, *arguments)")
    end
    assert_equal 0, STRICT.fetch("GENERIC_MAPPING_MISMATCH")
    # The five-argument FromStream was the last member left after this one, and the milestone that
    # followed closed it -- so the type is complete and its remainder is empty.
    assert_empty ReviewedScoreboard.partial_remainder(STRICT, NAME)
    assert_equal ReviewedScoreboard::MISSING_MEMBER, STRICT.fetch("MISSING_MEMBER")
  end

  # The element types both XNA's `T : struct` and CNA's `CNA_TextureDataType` model. `System.Byte[]`
  # projects to a Ruby String, so `::String` stands for `byte`.
  def test_the_element_type_table_matches_cnas_identities
    table = G::Texture2D::TEXTURE_DATA_TYPES
    assert_equal 11, table.length
    assert_equal [0, 4], table.fetch(F::Color)
    assert_equal [4, 1], table.fetch(::String), "byte, as a Ruby String"
    assert_equal [9, 8], table.fetch(G::PackedVector::Rgba64)
    constants = CNA::Native::Manifest::CONSTANTS
    assert_equal 0, constants.fetch("CNA_TEXTURE_DATA_COLOR")
    assert_equal 4, constants.fetch("CNA_TEXTURE_DATA_BYTE")
    assert_equal 10, constants.fetch("CNA_TEXTURE_DATA_ALPHA8")
    table.each_value do |(identity, _size)|
      assert_includes constants.values_at(*constants.keys.grep(/\ACNA_TEXTURE_DATA_/)), identity
    end
  end

  # ------------------------------------------------------------------------------ live behaviour

  class Host < F::Game
    attr_reader :result

    def initialize(&body)
      @body = body
      @result = nil
      super()
      F::GraphicsDeviceManager.new(self)
    end

    def LoadContent
      @result = @body.call(self.GraphicsDevice)
    ensure
      self.Exit
    end
  end

  def with_texture(width = 2, height = 2)
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = Host.new do |device|
      texture = G::Texture2D.new(device, width, height)
      begin
        yield texture
      ensure
        texture.Dispose
      end
    end
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  def colours = [F::Color.new(255, 0, 0, 255), F::Color.new(0, 255, 0, 255),
                 F::Color.new(0, 0, 255, 255), F::Color.new(255, 255, 255, 255)]

  # The whole point: what goes in comes back, byte for byte.
  def test_pixels_round_trip_exactly
    values = with_texture do |texture|
      written = colours
      texture.SetData(F::Color, written)
      read = Array.new(4) { F::Color.new(0, 0, 0, 0) }
      texture.GetData(F::Color, read)
      [written.map(&:PackedValue), read.map(&:PackedValue),
       read.map { |c| [c.R, c.G, c.B, c.A] }]
    end
    assert_equal values[0], values[1], "every packed value survives the round trip"
    assert_equal [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [255, 255, 255, 255]], values[2]
  end

  # The five-argument overload, which is the one that carries a level and a sub-rectangle.
  def test_a_sub_rectangle_writes_and_reads_just_that_region
    values = with_texture do |texture|
      texture.SetData(F::Color, colours)
      texture.SetData(F::Color, 0, F::Rectangle.new(1, 1, 1, 1), [F::Color.new(9, 9, 9, 255)], 0, 1)
      one = [F::Color.new(0, 0, 0, 0)]
      texture.GetData(F::Color, 0, F::Rectangle.new(1, 1, 1, 1), one, 0, 1)
      whole = Array.new(4) { F::Color.new(0, 0, 0, 0) }
      texture.GetData(F::Color, whole)
      [[one[0].R, one[0].G, one[0].B], whole.map { |c| [c.R, c.G, c.B] }]
    end
    assert_equal [9, 9, 9], values[0], "the sub-region reads back what was written into it"
    assert_equal [255, 0, 0], values[1][0], "and the other three pixels are untouched"
    assert_equal [9, 9, 9], values[1][3]
  end

  # `Helpers.ValidateCopyParameters` names **"dataIndex"** for the first failure, not the public
  # parameter's `startIndex`, and checks in that order: index, index + count, then count.
  def test_the_copy_parameter_validation_is_the_helpers_own
    values = with_texture do |texture|
      err = ->(&block) { begin; block.call; :ok; rescue => e; e.class; end }
      data = colours
      [err.call { texture.SetData(F::Color, data, -1, 4) },
       err.call { texture.SetData(F::Color, data, 5, 1) },
       err.call { texture.SetData(F::Color, data, 0, 5) },
       err.call { texture.SetData(F::Color, data, 0, 0) },
       err.call { texture.SetData(F::Color, data, 0, -1) },
       err.call { texture.SetData(F::Color, data, 0, 4) }]
    end
    assert_equal [RangeError] * 5, values[0..4]
    assert_equal :ok, values[5]
  end

  # `Texture.GetAndValidateRect` -- negative origin, non-positive extent, or reaching past the level.
  # `Texture.ValidateTotalSize` -- the elements must exactly fill the region.
  def test_the_rectangle_and_total_size_validation
    values = with_texture do |texture|
      err = ->(&block) { begin; block.call; :ok; rescue => e; e.class; end }
      one = [F::Color.new(1, 1, 1, 255)]
      [err.call { texture.SetData(F::Color, 0, F::Rectangle.new(-1, 0, 1, 1), one, 0, 1) },
       err.call { texture.SetData(F::Color, 0, F::Rectangle.new(0, -1, 1, 1), one, 0, 1) },
       err.call { texture.SetData(F::Color, 0, F::Rectangle.new(0, 0, 0, 1), one, 0, 1) },
       err.call { texture.SetData(F::Color, 0, F::Rectangle.new(0, 0, 1, 0), one, 0, 1) },
       err.call { texture.SetData(F::Color, 0, F::Rectangle.new(2, 0, 1, 1), one, 0, 1) },
       err.call { texture.SetData(F::Color, 0, F::Rectangle.new(0, 2, 1, 1), one, 0, 1) },
       err.call { texture.SetData(F::Color, colours, 0, 2) },
       err.call { texture.SetData(F::Color, 0, F::Rectangle.new(0, 0, 1, 1), one, 0, 1) }]
    end
    assert_equal [ArgumentError] * 6, values[0..5], "every rectangle failure is InvalidRectangle"
    assert_equal ArgumentError, values[6], "two elements do not fill a 2x2 texture"
    assert_equal :ok, values[7]
  end

  def test_null_data_a_wrong_element_type_and_a_disposed_texture_are_refused
    values = with_texture do |texture|
      err = ->(&block) { begin; block.call; :ok; rescue => e; e.class; end }
      [err.call { texture.SetData(F::Color, nil) },
       err.call { texture.SetData(Object, colours) },
       err.call { texture.SetData(F::Color, "abcd") },
       err.call { texture.SetData(F::Color, [1, 2, 3, 4]) },
       err.call { texture.SetData(F::Color) },
       err.call { texture.SetData(F::Color, colours, 0) }]
    end
    assert_equal ArgumentError, values[0]
    assert_equal [TypeError, TypeError, TypeError], values[1..3]
    assert_equal [ArgumentError, ArgumentError], values[4..5], "only three arities exist"
  end

  # DEVIATION, recorded: XNA reaches `CannotUseFormatTypeAsManualParameter` by asking the **adapter**
  # whether the element type suits the texture's format, and every adapter value is fabricated on
  # the qualified artifact. So that check is not reproduced from invented data, and CNA's own
  # refusal is what surfaces -- measured here rather than described.
  def test_an_element_type_the_format_does_not_take_is_refused_by_cna
    values = with_texture do |texture|
      texture.SetData(F::Color, colours)
      begin
        texture.GetData(::String, +"\0".b * 16)
        :ok
      rescue StandardError => error
        [error.class, error.message]
      end
    end
    assert_equal CNA::NativeError, values[0]
    assert_includes values[1], "format", "CNA names the format rule it is enforcing"
  end

  def test_a_disposed_texture_refuses_both
    values = with_texture do |texture|
      texture.Dispose
      err = ->(&block) { begin; block.call; :ok; rescue => e; e.class; end }
      [err.call { texture.SetData(F::Color, colours) },
       err.call { texture.GetData(F::Color, colours) }]
    end
    assert_equal [CNA::DisposedObjectError, CNA::DisposedObjectError], values
  end
end

# `Texture2D.FromStream`'s five-argument overload — the member that completed the type, and the one
# that found an upstream defect.
class Texture2DFromStreamTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.Texture2D"

  def test_texture2d_is_complete_and_the_partial_count_fell_again
    assert_includes STRICT.fetch("completeTypeNames"), NAME
    refute_includes STRICT.fetch("partialTypes").keys, NAME
    assert_equal ReviewedScoreboard::PARTIAL_TYPES, STRICT.fetch("PARTIAL_TYPES")
    assert_equal 3, STRICT.fetch("PARTIAL_TYPES"), "Texture2D was the fourth"
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
  end

  class Host < F::Game
    attr_reader :result

    def initialize(&body)
      @body = body
      @result = nil
      super()
      F::GraphicsDeviceManager.new(self)
    end

    def LoadContent
      @result = @body.call(self.GraphicsDevice, File.binread(ENV.fetch("CNA_TEST_PNG")))
    ensure
      self.Exit
    end
  end

  def with_device
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]
    skip "CNA_TEST_PNG not supplied" unless ENV["CNA_TEST_PNG"] && File.file?(ENV["CNA_TEST_PNG"])

    game = Host.new { |device, png| yield device, png }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  # Both overloads forward to one internal constructor; the two-argument form preserves the source
  # dimensions and the five-argument form passes a requested size and a `zoom` flag. CNA carries the
  # difference in `CNA_Texture2DDecodeInfo`, whose **null pointer is** the two-argument case.
  def test_the_two_argument_form_preserves_the_source_and_the_five_argument_form_resizes
    values = with_device do |device, png|
      decode = lambda do |*arguments|
        texture = G::Texture2D.FromStream(device, StringIO.new(png), *arguments)
        size = [texture.Width, texture.Height]
        texture.Dispose
        size
      end
      [decode.call, decode.call(64, 64, false), decode.call(64, 64, true), decode.call(256, 256, false)]
    end
    assert_equal [128, 128], values[0], "no decode info, so the source size survives"
    assert_equal [64, 64], values[1]
    assert_equal [64, 64], values[2]
    assert_equal [256, 256], values[3], "and it scales up as readily as down"
  end

  # `zoom=false` fits while preserving the aspect ratio, so a square source asked for 64x32 comes
  # back 32x32 rather than distorted.
  def test_fit_preserves_the_aspect_ratio_rather_than_distorting
    values = with_device do |device, png|
      texture = G::Texture2D.FromStream(device, StringIO.new(png), 64, 32, false)
      size = [texture.Width, texture.Height]
      texture.Dispose
      size
    end
    assert_equal [32, 32], values, "128x128 fitted into 64x32 is 32x32"
  end

  # UPSTREAM_CNA_DEFECT, reproduced rather than worked around: the cover-and-crop path is
  # **asymmetric**. From a square source a taller-than-wide target crops correctly and a
  # wider-than-tall one fails, which cover-and-crop cannot be by definition. Measured at the C ABI
  # too, with no Ruby in the path; `docs/texture-decode-upstream-defect.md` records the whole of it.
  #
  # If the upstream path is fixed, this test fails and says so.
  def test_the_zoom_path_is_asymmetric_and_the_binding_does_not_paper_over_it
    values = with_device do |device, png|
      attempt = lambda do |width, height|
        texture = G::Texture2D.FromStream(device, StringIO.new(png), width, height, true)
        size = [texture.Width, texture.Height]
        texture.Dispose
        size
      rescue StandardError => error
        error.class
      end
      [attempt.call(32, 64), attempt.call(64, 32), attempt.call(200, 100), attempt.call(64, 64)]
    end
    assert_equal [32, 64], values[0], "taller than wide crops and scales correctly"
    assert_equal CNA::NativeError, values[1], "wider than tall does not, which is the defect"
    assert_equal CNA::NativeError, values[2]
    assert_equal [64, 64], values[3], "and a matching aspect ratio is unaffected"
  end

  def test_the_five_argument_form_validates_what_the_constructor_validates
    values = with_device do |device, png|
      err = ->(&block) { begin; block.call.Dispose; :ok; rescue => e; e.class; end }
      [err.call { G::Texture2D.FromStream(nil, StringIO.new(png)) },
       err.call { G::Texture2D.FromStream(device, nil) },
       err.call { G::Texture2D.FromStream(device, StringIO.new(png), 0, 1, false) },
       err.call { G::Texture2D.FromStream(device, StringIO.new(png), 1, -1, false) },
       err.call { G::Texture2D.FromStream(device, StringIO.new(png), 1, 1, 1) },
       err.call { G::Texture2D.FromStream(device, StringIO.new(png), 1, 1) },
       err.call { G::Texture2D.FromStream(device, StringIO.new(+"")) }]
    end
    assert_equal [ArgumentError, ArgumentError], values[0..1]
    assert_equal [RangeError, RangeError], values[2..3], "ValidateCreationParameters, as the constructors use"
    assert_equal TypeError, values[4]
    assert_equal ArgumentError, values[5], "only two arities exist"
    assert_equal ArgumentError, values[6], "an empty stream carries no image"
  end
end
