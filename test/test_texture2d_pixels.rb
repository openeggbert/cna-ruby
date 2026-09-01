# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
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
    remainder = ReviewedScoreboard.partial_remainder(STRICT, NAME)
                                  .map { |entry| entry.split("::", 2).last.sub(/ \(\d+ overloads?\)\z/, "") }
    assert_equal %w[FromStream], remainder, "only the five-argument FromStream is left"
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
