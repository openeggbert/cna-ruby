# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require "stringio"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `Texture2D.SaveAsPng` and `SaveAsJpeg` — the first members of this binding that produce a real
# encoded image, and the first consumer of the `System.IO.Stream` projection on the *writing* side.
class Texture2DSaveTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.Texture2D"

  PNG_SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10].freeze
  JPEG_SIGNATURE = [255, 216, 255].freeze

  # ------------------------------------------------------------------- the contract, from metadata

  def test_both_members_are_selected_and_the_remainder_shrank
    %w[SaveAsPng SaveAsJpeg].each do |name|
      member = REFERENCE.fetch(NAME).fetch("members").find { |m| m.fetch("name") == name }
      assert_equal ["System.IO.Stream", "System.Int32", "System.Int32"],
                   member.fetch("parameters").map { |p| p.fetch("type") }
      assert G::Texture2D.public_method_defined?(name), name
    end
    remainder = ReviewedScoreboard.partial_remainder(STRICT, NAME)
                                  .map { |entry| entry.split("::", 2).last.sub(/ \(\d+ overloads?\)\z/, "") }
    refute_includes remainder, "SaveAsPng"
    refute_includes remainder, "SaveAsJpeg"
    assert_equal %w[.ctor FromStream SetData GetData].sort, remainder.sort
    assert_equal ReviewedScoreboard::MISSING_MEMBER, STRICT.fetch("MISSING_MEMBER")
  end

  # `SaveAsJpeg` is `SaveAsImage(stream, 0, w, h)` and `SaveAsPng` is `SaveAsImage(stream, 2, w, h)`,
  # and `SaveAsImage` validates the stream twice and the format once -- and the size **never**.
  def test_the_two_image_format_identities_are_the_ils_own
    constants = CNA::Native::Manifest::CONSTANTS
    assert_equal 0, constants.fetch("CNA_TEXTURE_IMAGE_FORMAT_PNG")
    assert_equal 1, constants.fetch("CNA_TEXTURE_IMAGE_FORMAT_JPEG")
    # CNA's identities are its own; XNA's private enum numbers them differently (JPEG 0, PNG 2),
    # which is exactly why the projection names the CNA constants rather than reusing XNA's literals.
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    assert_includes symbols, "cna_texture2d_get_encoded_byte_count"
    assert_includes symbols, "cna_texture2d_copy_encoded"
    refute_includes symbols, "cna_texture2d_save_file"
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
      device = self.GraphicsDevice
      texture = File.open(ENV.fetch("CNA_TEST_PNG"), "rb") { |s| G::Texture2D.FromStream(device, s) }
      @result = @body.call(texture)
    ensure
      self.Exit
    end
  end

  def with_texture
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]
    skip "CNA_TEST_PNG not supplied" unless ENV["CNA_TEST_PNG"] && File.file?(ENV["CNA_TEST_PNG"])

    game = Host.new { |texture| yield texture }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  # A real encode: the bytes carry the format's own signature, which is what makes this a
  # measurement rather than a byte count.
  def test_each_writes_a_real_image_with_its_own_signature
    values = with_texture do |texture|
      png = StringIO.new(+"".b)
      texture.SaveAsPng(png, texture.Width, texture.Height)
      jpeg = StringIO.new(+"".b)
      texture.SaveAsJpeg(jpeg, texture.Width, texture.Height)
      [[texture.Width, texture.Height], png.string, jpeg.string]
    end
    size, png, jpeg = values

    assert_equal [128, 128], size
    assert_operator png.bytesize, :>, 0
    assert_equal PNG_SIGNATURE, png.bytes.first(8), "the PNG signature, not a plausible byte count"
    assert_equal JPEG_SIGNATURE, jpeg.bytes.first(3), "SOI and the first marker"
    refute_equal png, jpeg, "two formats, two encodings"
  end

  # The projected `Stream` is accepted on the writing side, which is what its `Write` is for.
  def test_it_writes_into_the_projected_stream_as_well_as_a_ruby_io
    values = with_texture do |texture|
      stream = CNA::Runtime::Stream.over_bytes(+"".b, writable: true, name: "png")
      texture.SaveAsPng(stream, texture.Width, texture.Height)
      [stream.Length, stream.Position]
    end
    assert_operator values[0], :>, 8
    assert_equal values[0], values[1], "the stream is left at the end of what was written"
  end

  # `if (stream == null) throw ArgumentNullException("stream")` and
  # `if (!stream.CanWrite) throw ArgumentException("stream")` -- the only two the IL has.
  def test_the_two_stream_refusals_are_the_only_managed_ones
    values = with_texture do |texture|
      err = ->(&block) { begin; block.call; :ok; rescue => e; e.class; end }
      read_only = CNA::Runtime::Stream.over_bytes("x".b, writable: false, name: "ro")
      [err.call { texture.SaveAsPng(nil, 1, 1) },
       err.call { texture.SaveAsJpeg(nil, 1, 1) },
       err.call { texture.SaveAsPng(read_only, 1, 1) },
       err.call { texture.SaveAsPng(Object.new, 1, 1) },
       err.call { texture.SaveAsPng(StringIO.new(+"".b), "1", 1) }]
    end
    assert_equal [ArgumentError, ArgumentError, ArgumentError], values[0..2]
    assert_equal TypeError, values[3]
    assert_equal TypeError, values[4]
  end

  # DEVIATION, recorded: `SaveAsImage` validates the stream and the format and **nothing else** --
  # there is no width or height check in the IL at all, so XNA hands a zero size to its encoder.
  # CNA's encoder refuses it, and that refusal surfaces rather than a managed rule being invented.
  def test_a_zero_size_is_refused_by_cna_and_not_by_a_rule_this_binding_invented
    values = with_texture do |texture|
      err = ->(&block) { begin; block.call; :ok; rescue => e; e.class; end }
      [err.call { texture.SaveAsPng(StringIO.new(+"".b), 0, 0) },
       err.call { texture.SaveAsPng(StringIO.new(+"".b), -1, 1) },
       err.call { texture.SaveAsPng(StringIO.new(+"".b), 1, 1) }]
    end
    assert_equal CNA::NativeError, values[0]
    assert_equal CNA::NativeError, values[1]
    assert_equal :ok, values[2], "a one-pixel target really encodes"
  end

  def test_a_disposed_texture_refuses
    values = with_texture do |texture|
      texture.Dispose
      begin; texture.SaveAsPng(StringIO.new(+"".b), 1, 1); :ok; rescue => e; e.class; end
    end
    assert_equal CNA::DisposedObjectError, values
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_adds_no_pixel_access_or_second_from_stream_overload
    %i[SetData GetData].each { |absent| refute G::Texture2D.public_method_defined?(absent) }
    # `FromStream`'s five-argument overload, which scales on load, is still outstanding.
    assert_raises(ArgumentError) do
      G::Texture2D.FromStream(nil, StringIO.new(+"".b), 1, 1, false)
    rescue TypeError
      raise ArgumentError
    end
  end
end
