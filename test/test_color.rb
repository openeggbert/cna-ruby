# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/cna"

class ColorTest < Minitest::Test
  F = Microsoft::Xna::Framework
  Color = F::Color

  # Independently retained golden values from the 141 public Color property
  # bodies in Microsoft.Xna.Framework.dll SHA-256
  # 38e7093f52d7474bbc6256906519781a1210d7da50a1c667b52716fcf49ca130.
  GOLDEN_PALETTE = {
    "Transparent" => 0,
    "AliceBlue" => 4_294_965_488,
    "AntiqueWhite" => 4_292_340_730,
    "Aqua" => 4_294_967_040,
    "Aquamarine" => 4_292_149_119,
    "Azure" => 4_294_967_280,
    "Beige" => 4_292_670_965,
    "Bisque" => 4_291_093_759,
    "Black" => 4_278_190_080,
    "BlanchedAlmond" => 4_291_685_375,
    "Blue" => 4_294_901_760,
    "BlueViolet" => 4_293_012_362,
    "Brown" => 4_280_953_509,
    "BurlyWood" => 4_287_084_766,
    "CadetBlue" => 4_288_716_383,
    "Chartreuse" => 4_278_255_487,
    "Chocolate" => 4_280_183_250,
    "Coral" => 4_283_465_727,
    "CornflowerBlue" => 4_293_760_356,
    "Cornsilk" => 4_292_671_743,
    "Crimson" => 4_282_127_580,
    "Cyan" => 4_294_967_040,
    "DarkBlue" => 4_287_299_584,
    "DarkCyan" => 4_287_335_168,
    "DarkGoldenrod" => 4_278_945_464,
    "DarkGray" => 4_289_309_097,
    "DarkGreen" => 4_278_215_680,
    "DarkKhaki" => 4_285_249_469,
    "DarkMagenta" => 4_287_299_723,
    "DarkOliveGreen" => 4_281_297_749,
    "DarkOrange" => 4_278_226_175,
    "DarkOrchid" => 4_291_572_377,
    "DarkRed" => 4_278_190_219,
    "DarkSalmon" => 4_286_224_105,
    "DarkSeaGreen" => 4_287_347_855,
    "DarkSlateBlue" => 4_287_315_272,
    "DarkSlateGray" => 4_283_387_695,
    "DarkTurquoise" => 4_291_939_840,
    "DarkViolet" => 4_292_018_324,
    "DeepPink" => 4_287_829_247,
    "DeepSkyBlue" => 4_294_950_656,
    "DimGray" => 4_285_098_345,
    "DodgerBlue" => 4_294_938_654,
    "Firebrick" => 4_280_427_186,
    "FloralWhite" => 4_293_982_975,
    "ForestGreen" => 4_280_453_922,
    "Fuchsia" => 4_294_902_015,
    "Gainsboro" => 4_292_664_540,
    "GhostWhite" => 4_294_965_496,
    "Gold" => 4_278_245_375,
    "Goldenrod" => 4_280_329_690,
    "Gray" => 4_286_611_584,
    "Green" => 4_278_222_848,
    "GreenYellow" => 4_281_335_725,
    "Honeydew" => 4_293_984_240,
    "HotPink" => 4_290_013_695,
    "IndianRed" => 4_284_243_149,
    "Indigo" => 4_286_709_835,
    "Ivory" => 4_293_984_255,
    "Khaki" => 4_287_424_240,
    "Lavender" => 4_294_633_190,
    "LavenderBlush" => 4_294_308_095,
    "LawnGreen" => 4_278_254_716,
    "LemonChiffon" => 4_291_689_215,
    "LightBlue" => 4_293_318_829,
    "LightCoral" => 4_286_611_696,
    "LightCyan" => 4_294_967_264,
    "LightGoldenrodYellow" => 4_292_016_890,
    "LightGreen" => 4_287_688_336,
    "LightGray" => 4_292_072_403,
    "LightPink" => 4_290_885_375,
    "LightSalmon" => 4_286_226_687,
    "LightSeaGreen" => 4_289_376_800,
    "LightSkyBlue" => 4_294_626_951,
    "LightSlateGray" => 4_288_252_023,
    "LightSteelBlue" => 4_292_789_424,
    "LightYellow" => 4_292_935_679,
    "Lime" => 4_278_255_360,
    "LimeGreen" => 4_281_519_410,
    "Linen" => 4_293_325_050,
    "Magenta" => 4_294_902_015,
    "Maroon" => 4_278_190_208,
    "MediumAquamarine" => 4_289_383_782,
    "MediumBlue" => 4_291_624_960,
    "MediumOrchid" => 4_292_040_122,
    "MediumPurple" => 4_292_571_283,
    "MediumSeaGreen" => 4_285_641_532,
    "MediumSlateBlue" => 4_293_814_395,
    "MediumSpringGreen" => 4_288_346_624,
    "MediumTurquoise" => 4_291_613_000,
    "MediumVioletRed" => 4_286_911_943,
    "MidnightBlue" => 4_285_536_537,
    "MintCream" => 4_294_639_605,
    "MistyRose" => 4_292_994_303,
    "Moccasin" => 4_290_110_719,
    "NavajoWhite" => 4_289_584_895,
    "Navy" => 4_286_578_688,
    "OldLace" => 4_293_326_333,
    "Olive" => 4_278_222_976,
    "OliveDrab" => 4_280_520_299,
    "Orange" => 4_278_232_575,
    "OrangeRed" => 4_278_207_999,
    "Orchid" => 4_292_243_674,
    "PaleGoldenrod" => 4_289_390_830,
    "PaleGreen" => 4_288_215_960,
    "PaleTurquoise" => 4_293_848_751,
    "PaleVioletRed" => 4_287_852_763,
    "PapayaWhip" => 4_292_210_687,
    "PeachPuff" => 4_290_370_303,
    "Peru" => 4_282_353_101,
    "Pink" => 4_291_543_295,
    "Plum" => 4_292_714_717,
    "PowderBlue" => 4_293_320_880,
    "Purple" => 4_286_578_816,
    "Red" => 4_278_190_335,
    "RosyBrown" => 4_287_598_524,
    "RoyalBlue" => 4_292_962_625,
    "SaddleBrown" => 4_279_453_067,
    "Salmon" => 4_285_694_202,
    "SandyBrown" => 4_284_523_764,
    "SeaGreen" => 4_283_927_342,
    "SeaShell" => 4_293_850_623,
    "Sienna" => 4_281_160_352,
    "Silver" => 4_290_822_336,
    "SkyBlue" => 4_293_643_911,
    "SlateBlue" => 4_291_648_106,
    "SlateGray" => 4_287_660_144,
    "Snow" => 4_294_638_335,
    "SpringGreen" => 4_286_578_432,
    "SteelBlue" => 4_290_019_910,
    "Tan" => 4_287_411_410,
    "Teal" => 4_286_611_456,
    "Thistle" => 4_292_394_968,
    "Tomato" => 4_282_868_735,
    "Turquoise" => 4_291_878_976,
    "Violet" => 4_293_821_166,
    "Wheat" => 4_289_978_101,
    "White" => 4_294_967_295,
    "WhiteSmoke" => 4_294_309_365,
    "Yellow" => 4_278_255_615,
    "YellowGreen" => 4_281_519_514
  }.freeze

  def bits(value) = [value].pack("e").unpack1("L<")
  def channels(value) = [value.R, value.G, value.B, value.A]

  def test_constructor_dispatch_and_integer_clamping
    assert_equal [0, 0, 0, 0], channels(Color.new)
    assert_equal [255, 0, 1, 255], channels(Color.new(300, -2, 1, 999))
    assert_equal [1, 2, 3, 255], channels(Color.new(1, 2, 3))
    assert_raises(RangeError) { Color.new(2_147_483_648, 0, 0) }
    assert_raises(TypeError) { Color.new(1, 0.5, 2) }
    assert_raises(TypeError) { Color.new(1.0, 0.5, 2) }
    assert_raises(TypeError) { Color.new(F::Vector2.Zero) }
    assert_raises(ArgumentError) { Color.new(1, 2) }
  end

  def test_single_constructor_pack_unorm_edges_and_ties
    assert_equal [0, 255, 128, 255], channels(Color.new(0.0, 1.0, 0.5, Float::INFINITY))
    assert_equal [0, 0, 255, 0], channels(Color.new(-Float::INFINITY, Float::NAN, Float::INFINITY, -Float::INFINITY))

    smallest = [1].pack("L<").unpack1("e")
    below_one = [0x3f7f_ffff].pack("L<").unpack1("e")
    above_one = [0x3f80_0001].pack("L<").unpack1("e")
    assert_equal [0, 0, 255, 255], channels(Color.new(-smallest, smallest, below_one, above_one))

    tie_zero = CNA::Runtime::Numeric.div32(0.5, 255.0)
    tie_two = CNA::Runtime::Numeric.div32(2.5, 255.0)
    assert_equal [0, 2, 0, 2], channels(Color.new(tie_zero, tie_two, tie_zero, tie_two))
  end

  def test_vector_constructors_copy_and_default_alpha
    vector3 = F::Vector3.new(0.5, 0.25, 1.0)
    vector4 = F::Vector4.new(1.0, 0.5, 0.25, 0.0)
    from3 = Color.new(vector3)
    from4 = Color.new(vector4)
    assert_equal [128, 64, 255, 255], channels(from3)
    assert_equal [255, 128, 64, 0], channels(from4)
    vector3.X = 0.0
    vector4.X = 0.0
    assert_equal 128, from3.R
    assert_equal 255, from4.R
  end

  def test_vector_normalization_has_binary32_results_and_fresh_values
    color = Color.new(0, 1, 127, 128)
    vector3 = color.ToVector3
    vector4 = Color.new(254, 255, 1, 127).ToVector4
    assert_equal [0x0000_0000, 0x3b80_8081, 0x3efe_feff], [vector3.X, vector3.Y, vector3.Z].map { |value| bits(value) }
    assert_equal [0x3f7e_feff, 0x3f80_0000, 0x3b80_8081, 0x3efe_feff],
                 [vector4.X, vector4.Y, vector4.Z, vector4.W].map { |value| bits(value) }
    refute_same color.ToVector3, color.ToVector3
    refute_same color.ToVector4, color.ToVector4
  end

  def test_vector_from_non_premultiplied
    assert_equal [0, 0, 0, 0], channels(Color.FromNonPremultiplied(F::Vector4.new(1.0, 0.5, 0.25, 0.0)))
    assert_equal [51, 102, 153, 255], channels(Color.FromNonPremultiplied(F::Vector4.new(0.2, 0.4, 0.6, 1.0)))
    assert_equal [128, 64, 32, 128], channels(Color.FromNonPremultiplied(F::Vector4.new(1.0, 0.5, 0.25, 0.5)))
    assert_equal [0, 255, 0, 255], channels(Color.FromNonPremultiplied(F::Vector4.new(Float::NAN, Float::INFINITY, -Float::INFINITY, Float::INFINITY)))
    assert_raises(TypeError) { Color.FromNonPremultiplied(F::Vector3.Zero) }
  end

  def test_integer_from_non_premultiplied_boundaries_and_extremes
    [
      [0, [0, 0, 0, 0]],
      [1, [1, 0, 0, 1]],
      [127, [127, 63, 31, 127]],
      [128, [128, 64, 32, 128]],
      [254, [254, 127, 63, 254]],
      [255, [255, 128, 64, 255]]
    ].each do |alpha, expected|
      assert_equal expected, channels(Color.FromNonPremultiplied(255, 128, 64, alpha))
    end
    assert_equal 0xffff_ffff, Color.FromNonPremultiplied(2_147_483_647, 2_147_483_647, 2_147_483_647, 2_147_483_647).PackedValue
    assert_equal [255, 255, 255, 0], channels(Color.FromNonPremultiplied(-2_147_483_648, -2_147_483_648, -2_147_483_648, -2_147_483_648))
    assert_raises(RangeError) { Color.FromNonPremultiplied(2_147_483_648, 0, 0, 0) }
  end

  def test_packed_value_layout_and_setter_domain
    assert_equal 0x0403_0201, Color.new(1, 2, 3, 4).PackedValue
    masks = [[0x0000_00ff, [255, 0, 0, 0]], [0x0000_ff00, [0, 255, 0, 0]],
             [0x00ff_0000, [0, 0, 255, 0]], [0xff00_0000, [0, 0, 0, 255]]]
    masks.each do |packed, expected|
      value = Color.new
      value.PackedValue = packed
      assert_equal expected, channels(value)
    end
    value = Color.new
    value.PackedValue = 0xffff_ffff
    assert_equal [255, 255, 255, 255], channels(value)
    assert_raises(RangeError) { value.PackedValue = -1 }
    assert_raises(RangeError) { value.PackedValue = 0x1_0000_0000 }
    assert_raises(TypeError) { value.PackedValue = 1.0 }
  end

  def test_channel_setters_are_exact_byte_properties
    value = Color.new
    value.R = 1
    value.G = 2
    value.B = 3
    value.A = 4
    assert_equal 0x0403_0201, value.PackedValue
    assert_raises(RangeError) { value.R = -1 }
    assert_raises(RangeError) { value.G = 256 }
    assert_raises(TypeError) { value.B = 1.0 }
  end

  def test_lerp_fixed_point_clamp_rounding_and_nonfinite_amounts
    low = Color.new(10, 200, 50, 255)
    high = Color.new(110, 0, 250, 0)
    assert_equal channels(low), channels(Color.Lerp(low, high, -1.0))
    assert_equal channels(low), channels(Color.Lerp(low, high, 0.0))
    assert_equal [60, 100, 150, 127], channels(Color.Lerp(low, high, 0.5))
    assert_equal channels(high), channels(Color.Lerp(low, high, 1.0))
    assert_equal channels(high), channels(Color.Lerp(low, high, 2.0))
    assert_equal channels(low), channels(Color.Lerp(low, high, Float::NAN))
    assert_equal channels(high), channels(Color.Lerp(low, high, Float::INFINITY))
    assert_equal channels(low), channels(Color.Lerp(low, high, -Float::INFINITY))
    assert_equal [127, 127, 127, 127], channels(Color.Lerp(Color.new(255, 255, 255, 255), Color.new(0, 0, 0, 0), 0.5))
  end

  def test_multiply_fixed_point_saturation_and_nonfinite_scales
    value = Color.new(1, 100, 200, 255)
    assert_equal [0, 0, 0, 0], channels(Color.Multiply(value, 0.0))
    assert_equal channels(value), channels(Color.Multiply(value, 1.0))
    assert_equal [0, 50, 100, 127], channels(Color.Multiply(value, 0.5))
    assert_equal [0, 0, 0, 0], channels(Color.Multiply(value, -1.0))
    assert_equal [2, 200, 255, 255], channels(Color.Multiply(value, 2.0))
    assert_equal [0, 0, 0, 0], channels(Color.Multiply(value, Float::NAN))
    assert_equal [255, 255, 255, 255], channels(Color.Multiply(value, Float::INFINITY))
    assert_equal [0, 0, 0, 0], channels(Color.Multiply(value, -Float::INFINITY))
    assert_equal Color.Multiply(value, 0.5), value * 0.5
  end

  def test_full_authoritative_palette_and_transparent
    assert_equal 141, GOLDEN_PALETTE.length
    GOLDEN_PALETTE.each do |name, packed|
      assert_respond_to Color, name
      assert_equal packed, Color.public_send(name).PackedValue, name
    end
    assert_equal [0, 0, 0, 0], channels(Color.Transparent)
    assert_equal [100, 149, 237, 255], channels(Color.CornflowerBlue)
  end

  def test_named_properties_and_value_results_are_fresh
    first = Color.Red
    second = Color.Red
    refute_same first, second
    assert_equal first, second
    first.R = 0
    assert_equal 255, second.R

    original = Color.new(1, 2, 3, 4)
    copy = original.dup
    cloned = original.clone
    copy.R = 9
    cloned.G = 8
    assert_equal [1, 2, 3, 4], channels(original)
  end

  def test_equality_signed_hash_and_string
    value = Color.new(1, 2, 3, 255)
    same = Color.new(1, 2, 3, 255)
    different = Color.new(1, 2, 4, 255)
    assert value.Equals(same)
    assert_equal value, same
    refute_equal value, different
    assert value != different
    refute value.Equals(Object.new)
    assert_equal(-16_580_095, value.GetHashCode)
    assert_equal(-1, Color.White.GetHashCode)
    assert_equal 0, Color.Transparent.GetHashCode
    assert_equal "{R:1 G:2 B:3 A:255}", value.ToString
    assert_equal "{R:0 G:0 B:0 A:0}", Color.Transparent.ToString
    assert_equal "{R:255 G:255 B:255 A:255}", Color.White.ToString
  end
end
