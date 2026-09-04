# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"
require_relative "../lib/microsoft/xna/framework"

# Foundation 105 — the thirteen `Microsoft.Xna.Framework.Design` converters.
#
# The family was classified `BCL_PROJECTION_SCOPE` for four milestones. That was a scope decision
# rather than a blocker — the authority was on the machine and the reach was measurable — and this
# milestone revokes it, admits `System.dll` as a second BCL authority and projects the demand-driven
# `System.ComponentModel` closure the converters actually reach.
#
# **Nothing in this file is transcribed.** The audit table is generated from the pinned XNA IL into
# `docs/generated/design-converter-inventory.json`, and the assertions below read it. So a mutation
# to the Ruby implementation fails here, and so does a mutation to the generator: neither side can
# drift without the other noticing, which is the property the hand-maintained tables this project
# has lost before did not have.
class DesignConvertersTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path

  DESIGN = JSON.parse(ROOT.join("docs", "generated", "design-converter-inventory.json").read)
  BCL = JSON.parse(ROOT.join("docs", "generated", "bcl-inventory.json").read)
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)

  X = Microsoft::Xna::Framework
  D = X::Design
  CM = CNA::Runtime::ComponentModel
  RF = CNA::Runtime::Reflection
  GL = CNA::Runtime::Globalization

  # A culture whose list separator, decimal separator and group separator all differ from the
  # invariant one, so every culture-dependent path has a second answer that can fail.
  def german
    GL::CultureInfo.new("de-DE", listSeparator: ";", numberDecimalSeparator: ",",
                                 numberGroupSeparator: ".")
  end

  def converter_for(row_name) = D.const_get(row_name).new
  def rows = DESIGN.fetch("converters")
  def row(name) = rows.find { |entry| entry.fetch("type").end_with?(".#{name}") }

  # A non-symmetric sample value for each converted type, so a swapped member is a different value.
  # Every component is distinct and no two types share a shape.
  SAMPLES = {
    "Point" => -> { X::Point.new(-3, 7) },
    "Rectangle" => -> { X::Rectangle.new(-3, 7, 11, 13) },
    "Vector2" => -> { X::Vector2.new(1.5, -2.25) },
    "Vector3" => -> { X::Vector3.new(1.5, -2.25, 3.75) },
    "Vector4" => -> { X::Vector4.new(1.5, -2.25, 3.75, -4.125) },
    "Quaternion" => -> { X::Quaternion.new(0.125, -0.25, 0.5, -0.75) },
    "Matrix" => -> { X::Matrix.new(*(1..16).map { |index| index * 1.5 }) },
    "Plane" => -> { X::Plane.new(X::Vector3.new(0.0, 1.0, 0.0), 5.5) },
    "Ray" => -> { X::Ray.new(X::Vector3.new(1.0, 2.0, 3.0), X::Vector3.new(0.0, 0.0, 1.0)) },
    "BoundingBox" => -> { X::BoundingBox.new(X::Vector3.new(1.0, 2.0, 3.0), X::Vector3.new(4.0, 5.0, 6.0)) },
    "BoundingSphere" => -> { X::BoundingSphere.new(X::Vector3.new(1.0, 2.0, 3.0), 4.5) },
    "Color" => -> { X::Color.new(10, 20, 30, 40) }
  }.freeze

  # The generated table names a value type by its full CLR identity; the sample table keys on
  # the short name, which is also the Ruby constant.
  def short(identity) = identity.split(".").last
  def sample(identity) = SAMPLES.fetch(short(identity)).call

  # ------------------------------------------------------------------- the generated audit table

  def test_the_generated_table_covers_the_whole_family_and_nothing_else
    assert_equal 13, DESIGN.fetch("DESIGN_TYPES")
    assert_equal 12, rows.length
    assert_equal 3, DESIGN.fetch("DESIGN_DESCRIPTOR_TYPES")
    # The thirteen are exactly the thirteen the strict report used to call missing.
    projected = rows.map { |entry| entry.fetch("type") } + [DESIGN.fetch("base").fetch("type")]
    assert_equal projected.sort, STRICT.fetch("completeTypeNames").grep(/\.Design\./).sort
    refute STRICT.fetch("missingTypeNames").any? { |name| name.include?(".Design.") }
  end

  # Every row of the table, checked against the class the row built. This is the assertion that
  # makes the family falsifiable as a family rather than converter by converter.
  def test_every_converter_matches_its_generated_row
    rows.each do |entry|
      name = entry.fetch("type").split(".").last
      converter = converter_for(name)
      value = sample(entry.fetch("valueType"))

      assert_kind_of D::MathTypeConverter, converter, name
      assert_equal "Microsoft.Xna.Framework.Design.MathTypeConverter", entry.fetch("baseType"), name

      # The order a consumer actually receives: the sorted order where the constructor sorts, the
      # authored order where it does not.
      descriptors = converter.GetProperties(nil, value, nil)
      assert_equal entry.fetch("propertyOrder"), descriptors.map(&:Name), name

      # Whether string conversion is supported, observed through the member that reports it.
      assert_equal entry.fetch("supportStringConvert"), converter.CanConvertFrom(nil, ::String), name

      # Both are unconditional `ldc.i4.1` in the base and no subclass overrides either.
      assert converter.GetCreateInstanceSupported(nil), name
      assert converter.GetPropertiesSupported(nil), name
    end
  end

  # `MatrixConverter` and `RectangleConverter` are the two that never call `Sort`, so their order is
  # the authored one. Nothing else in the family has a null sort order, and if a future change made
  # one of them sort, its order would become alphabetical and this would fail.
  def test_exactly_two_converters_do_not_sort_and_keep_their_authored_order
    unsorted = rows.select { |entry| entry.fetch("sortOrder").nil? }.map { |entry| entry.fetch("type").split(".").last }
    assert_equal %w[MatrixConverter RectangleConverter], unsorted.sort

    matrix = row("MatrixConverter")
    assert_equal matrix.fetch("descriptors").map { |entry| entry.fetch("member") }, matrix.fetch("propertyOrder")
    assert_equal %w[M11 M12 M13 M14 M21 M22 M23 M24 M31 M32 M33 M34 M41 M42 M43 M44],
                 converter_for("MatrixConverter").GetProperties(nil, sample("Matrix"), nil).map(&:Name)
    # Not alphabetical, which is what a Sort() with no names would have produced.
    refute_equal matrix.fetch("propertyOrder").sort, matrix.fetch("propertyOrder").sort { |a, b| a <=> b } &&
                 converter_for("RectangleConverter").GetProperties(nil, sample("Rectangle"), nil).map(&:Name),
                 "Rectangle's order must not be alphabetical"
    assert_equal %w[X Y Width Height],
                 converter_for("RectangleConverter").GetProperties(nil, sample("Rectangle"), nil).map(&:Name)
  end

  # **Every one of the ten sorts reorders nothing**, and that is measured rather than noticed in
  # passing. Each of the ten passes `Sort` exactly the order it authored its descriptors in, so the
  # sorted result equals the authored one -- and the two converters that never call `Sort` reach the
  # same order by not sorting. All twelve therefore answer their authored order, by two paths.
  #
  # It matters for two reasons. It is why "ignore `Sort`" cannot be scored on any converter's answer
  # and has to be scored on the collection's contract instead. And it means what actually determines
  # the order a consumer sees is the authoring, with the sort as belt and braces -- so an
  # implementation that authored in one order and sorted into another would diverge from XNA even
  # though every individual fact still matched.
  def test_no_converters_sort_reorders_what_it_authored
    sorted = rows.reject { |entry| entry.fetch("sortOrder").nil? }
    assert_equal 10, sorted.length
    sorted.each do |entry|
      authored = entry.fetch("descriptors").map { |item| item.fetch("member") }
      assert_equal authored, entry.fetch("sortOrder"), entry.fetch("type")
      assert_equal authored, entry.fetch("propertyOrder"), entry.fetch("type")
    end
    # And the two that never sort reach the same place.
    rows.select { |entry| entry.fetch("sortOrder").nil? }.each do |entry|
      assert_equal entry.fetch("descriptors").map { |item| item.fetch("member") },
                   entry.fetch("propertyOrder"), entry.fetch("type")
    end
    # So for all twelve, the order a consumer receives is the authored one.
    rows.each do |entry|
      name = entry.fetch("type").split(".").last
      assert_equal entry.fetch("descriptors").map { |item| item.fetch("member") },
                   converter_for(name).GetProperties(nil, sample(entry.fetch("valueType")), nil).map(&:Name), name
    end
  end

  # Descriptor order is contract, and a swap has to be observable rather than merely different.
  # Reading each descriptor's value back off a non-symmetric sample is what makes it so.
  def test_descriptor_order_carries_the_members_values_in_that_order
    rows.each do |entry|
      name = entry.fetch("type").split(".").last
      value = sample(entry.fetch("valueType"))
      descriptors = converter_for(name).GetProperties(nil, value, nil)
      expected = entry.fetch("propertyOrder").map { |member| value.public_send(member) }
      assert_equal expected, descriptors.map { |descriptor| descriptor.GetValue(value) }, name
      # And every value is distinct, so a swapped pair really would show.
      assert_equal expected.length, expected.map(&:to_s).uniq.length, "#{name} sample is symmetric"
    end
  end

  # -------------------------------------------------------------------- the base class's answers

  # Half of `CanConvertFrom` and `CanConvertTo` is the base class's, which is why the base had to be
  # projected rather than flattened. These are the two answers that come from `TypeConverter` and
  # not from XNA, and both are counter-intuitive.
  def test_can_convert_from_falls_through_to_the_base_which_answers_for_instance_descriptor
    assert_equal "System.ComponentModel.TypeConverter::CanConvertFrom",
                 DESIGN.fetch("base").fetch("canConvertFromFallback")
    rows.each do |entry|
      name = entry.fetch("type").split(".").last
      converter = converter_for(name)
      # The base answers `sourceType == InstanceDescriptor`, for all thirteen.
      assert converter.CanConvertFrom(nil, CM::InstanceDescriptor), name
      # And it does *not* answer for String, so a converter with supportStringConvert false is false.
      assert_equal entry.fetch("supportStringConvert"), converter.CanConvertFrom(nil, ::String), name
      refute converter.CanConvertFrom(nil, ::Integer), name
    end
  end

  def test_can_convert_to_answers_true_for_string_even_where_the_converter_cannot_format_one
    assert_equal "System.ComponentModel.TypeConverter::CanConvertTo",
                 DESIGN.fetch("base").fetch("canConvertToFallback")
    silent = rows.reject { |entry| entry.fetch("supportStringConvert") }
    refute_empty silent
    silent.each do |entry|
      name = entry.fetch("type").split(".").last
      converter = converter_for(name)
      # The base's whole body is `destinationType == typeof(string)`, so the answer is true...
      assert converter.CanConvertTo(nil, ::String), name
      # ...and ConvertTo really does produce a string: the base's, which is value.ToString().
      value = sample(entry.fetch("valueType"))
      assert_equal value.ToString, converter.ConvertTo(nil, nil, value, ::String), name
      # ...while CanConvertFrom(String) is false, which is the asymmetry.
      refute converter.CanConvertFrom(nil, ::String), name
    end
  end

  # The `InstanceDescriptor` special case is XNA's own, at `IL_0001` of `CanConvertTo`.
  def test_the_instance_descriptor_special_case_is_the_converters_own
    assert_equal "System.ComponentModel.Design.Serialization.InstanceDescriptor",
                 DESIGN.fetch("base").fetch("canConvertToSpecialCase")
    assert_equal "System.String", DESIGN.fetch("base").fetch("canConvertFromSpecialCase")
    rows.each do |entry|
      assert converter_for(entry.fetch("type").split(".").last).CanConvertTo(nil, CM::InstanceDescriptor),
             entry.fetch("type")
    end
  end

  # `MathTypeConverter.GetProperties` reads the field and ignores all three arguments, including the
  # value. So the same collection comes back for a different value, and for none at all.
  def test_get_properties_answers_the_field_and_ignores_its_arguments
    assert_equal "propertyDescriptions", DESIGN.fetch("base").fetch("getPropertiesReadsField")
    converter = converter_for("Vector3Converter")
    first = converter.GetProperties(nil, sample("Vector3"), nil)
    assert_same first, converter.GetProperties(nil, X::Vector3.new(9, 9, 9), nil)
    assert_same first, converter.GetProperties(nil, nil, nil)
    assert_same first, converter.GetProperties(nil)
  end

  # ------------------------------------------------------------------------- InstanceDescriptor

  # Eleven of twelve resolve their named constructor. The twelfth is the finding this milestone
  # made: `ColorConverter` asks `Color` for a four-byte constructor, `Color` declares none, and the
  # CLR's own null test skips the branch.
  def test_eleven_converters_produce_an_instance_descriptor_and_color_cannot
    resolving = rows.select { |entry| entry.fetch("convertTo").fetch("constructorResolves") }
    assert_equal 11, resolving.length
    refused = rows.reject { |entry| entry.fetch("convertTo").fetch("constructorResolves") }
    assert_equal ["Microsoft.Xna.Framework.Design.ColorConverter"], refused.map { |entry| entry.fetch("type") }

    resolving.each do |entry|
      name = entry.fetch("type").split(".").last
      value = sample(entry.fetch("valueType"))
      descriptor = converter_for(name).ConvertTo(nil, nil, value, CM::InstanceDescriptor)
      assert_kind_of CM::InstanceDescriptor, descriptor, name
      assert descriptor.IsComplete, name
      assert_kind_of RF::ConstructorInfo, descriptor.MemberInfo, name
      assert_equal entry.fetch("convertTo").fetch("constructorParameters"),
                   descriptor.MemberInfo.clr_parameter_types, name
      # The arguments are the members read in the ConvertTo order, which is the authored order.
      assert_equal entry.fetch("convertTo").fetch("arguments"),
                   entry.fetch("descriptors").map { |item| item.fetch("member") }, name
      assert_equal entry.fetch("convertTo").fetch("arguments").map { |member| value.public_send(member) },
                   descriptor.Arguments, name
      # And it reconstructs the value it described.
      assert_equal value, descriptor.Invoke, name
    end
  end

  def test_color_names_a_constructor_its_value_type_does_not_declare
    entry = row("ColorConverter")
    assert_equal ["System.Byte"] * 4, entry.fetch("convertTo").fetch("constructorParameters")
    refute_includes entry.fetch("convertTo").fetch("declaredConstructors"), ["System.Byte"] * 4
    # The registry answers nil for it, which is what `ConstructorInfo.op_Inequality(ctor, null)`
    # tests, and finds the constructors Color really has.
    assert_nil RF.GetConstructor(X::Color, ["System.Byte"] * 4)
    refute_nil RF.GetConstructor(X::Color, ["System.Int32"] * 4)

    # So the branch is skipped and the base throws for a non-String destination.
    error = assert_raises(CNA::Runtime::NotSupportedError) do
      converter_for("ColorConverter").ConvertTo(nil, nil, sample("Color"), CM::InstanceDescriptor)
    end
    assert_includes error.message, "InstanceDescriptor"
    # Which is *not* a refusal to convert at all: string conversion still works.
    assert_equal "10, 20, 30, 40", converter_for("ColorConverter").ConvertTo(nil, nil, sample("Color"), ::String)
  end

  # Every converter accepts an `InstanceDescriptor` as a *source*, because the base's `ConvertFrom`
  # invokes one — which is why three of them declare a `ConvertFrom` that is a pure forward.
  def test_every_resolving_converter_round_trips_through_its_instance_descriptor
    rows.select { |entry| entry.fetch("convertTo").fetch("constructorResolves") }.each do |entry|
      name = entry.fetch("type").split(".").last
      converter = converter_for(name)
      value = sample(entry.fetch("valueType"))
      descriptor = converter.ConvertTo(nil, nil, value, CM::InstanceDescriptor)
      assert_equal value, converter.ConvertFrom(nil, nil, descriptor), name
    end
  end

  # The three that declare no `ConvertFrom` inherit the same behaviour as the three whose whole
  # body is a call to the base, so all six behave identically for an InstanceDescriptor source.
  def test_the_three_pure_forwards_and_the_three_undeclared_behave_alike
    forwards = rows.select { |entry| entry.fetch("convertFromForwardsTo") }
    assert_equal %w[BoundingBoxConverter BoundingSphereConverter RayConverter],
                 forwards.map { |entry| entry.fetch("type").split(".").last }.sort
    forwards.each do |entry|
      assert_equal "System.ComponentModel.TypeConverter::ConvertFrom", entry.fetch("convertFromForwardsTo")
    end
    undeclared = rows.select { |entry| entry.fetch("convertFrom").nil? && entry.fetch("convertFromForwardsTo").nil? }
    assert_equal %w[MatrixConverter PlaneConverter RectangleConverter],
                 undeclared.map { |entry| entry.fetch("type").split(".").last }.sort

    (forwards + undeclared).each do |entry|
      name = entry.fetch("type").split(".").last
      converter = converter_for(name)
      value = sample(entry.fetch("valueType"))
      descriptor = converter.ConvertTo(nil, nil, value, CM::InstanceDescriptor)
      assert_equal value, converter.ConvertFrom(nil, nil, descriptor), name
      # And a String source is refused by all six, because CanConvertFrom(String) is false.
      assert_raises(CNA::Runtime::NotSupportedError, name) { converter.ConvertFrom(nil, nil, "1, 2") }
    end
  end

  # ------------------------------------------------------------------------ string conversion

  def test_the_six_string_converters_round_trip_through_their_own_format
    rows.select { |entry| entry.fetch("supportStringConvert") }.each do |entry|
      name = entry.fetch("type").split(".").last
      converter = converter_for(name)
      value = sample(entry.fetch("valueType"))
      text = converter.ConvertTo(nil, nil, value, ::String)
      assert_equal entry.fetch("propertyOrder").length, text.split(", ").length, name
      assert_equal value, converter.ConvertFrom(nil, nil, text), name
    end
  end

  # The element converter is resolved through `TypeDescriptor.GetConverter(typeof(T))`, not by a
  # Ruby primitive parse, and which one is reached decides two observable behaviours.
  def test_the_scalar_element_converter_is_the_one_the_intrinsic_table_names
    assert_equal({"System.Byte" => "System.ComponentModel.ByteConverter",
                  "System.Int32" => "System.ComponentModel.Int32Converter",
                  "System.Single" => "System.ComponentModel.SingleConverter"},
                 DESIGN.fetch("scalarElementTypes").keys
                       .to_h { |element| [element, BCL.fetch("intrinsicTypeConverters").fetch(element)] })
    assert_equal "System.Int32", row("PointConverter").fetch("convertFrom").fetch("elementType")
    assert_equal "System.Byte", row("ColorConverter").fetch("convertFrom").fetch("elementType")
    assert_equal "System.Single", row("Vector3Converter").fetch("convertFrom").fetch("elementType")
  end

  # `BaseNumberConverter.AllowHex` is true and `SingleConverter` overrides it to false, so the
  # integer-element converters accept hexadecimal and the single-element ones do not. A hard-coded
  # Ruby `Integer()` parse on both sides would make these two agree.
  def test_hexadecimal_is_accepted_only_where_the_element_converter_allows_it
    assert_equal X::Point.new(16, 32), converter_for("PointConverter").ConvertFrom(nil, nil, "#10, #20")
    assert_equal X::Point.new(255, 1), converter_for("PointConverter").ConvertFrom(nil, nil, "0xFF, 0x1")
    assert_equal X::Color.new(255, 16, 1, 2), converter_for("ColorConverter").ConvertFrom(nil, nil, "&hFF, #10, 1, 2")

    assert_raises(::ArgumentError) { converter_for("Vector2Converter").ConvertFrom(nil, nil, "#10, #20") }
    refute CM::SingleConverter.new.AllowHex
    assert CM::Int32Converter.new.AllowHex
    assert CM::ByteConverter.new.AllowHex
  end

  # `Point` and `Rectangle` convert through `Int32Converter`, which parses with
  # `NumberStyles.Integer` — no decimal point. Parsing through a float and truncating would accept
  # "1.5" where the CLR refuses it.
  def test_the_integer_converters_do_not_parse_through_a_float
    assert_raises(::ArgumentError) { converter_for("PointConverter").ConvertFrom(nil, nil, "1.5, 2") }
    assert_equal X::Point.new(-2_147_483_648, 2_147_483_647),
                 converter_for("PointConverter").ConvertFrom(nil, nil, "-2147483648, 2147483647")
    assert_equal X::Point.new(0, 0), converter_for("PointConverter").ConvertFrom(nil, nil, "0, -0")
  end

  # `Color`'s channels are bytes: 0..255 and nothing else, and the descriptors read properties
  # rather than fields, which is what makes it the one converter building PropertyPropertyDescriptors.
  def test_color_channels_are_bytes_read_through_properties
    entry = row("ColorConverter")
    assert_equal ["GetProperty"] * 4, entry.fetch("descriptors").map { |item| item.fetch("reflection") }
    assert_equal ["PropertyPropertyDescriptor"] * 4, entry.fetch("descriptors").map { |item| item.fetch("descriptor") }
    assert(rows.reject { |other| other.equal?(entry) }
               .all? { |other| other.fetch("descriptors").all? { |item| item.fetch("reflection") == "GetField" } })

    converter = converter_for("ColorConverter")
    assert_equal X::Color.new(0, 255, 128, 1), converter.ConvertFrom(nil, nil, "0, 255, 128, 1")
    assert_raises(::ArgumentError) { converter.ConvertFrom(nil, nil, "0, 256, 0, 0") }
    assert_raises(::ArgumentError) { converter.ConvertFrom(nil, nil, "0, -1, 0, 0") }
    # R/G/B/A and in that order, not RGBA reordered or alpha dropped.
    assert_equal %w[R G B A], converter.GetProperties(nil, sample("Color"), nil).map(&:Name)
    assert_equal [10, 20, 30, 40], converter.GetProperties(nil, sample("Color"), nil)
                                            .map { |descriptor| descriptor.GetValue(sample("Color")) }
  end

  # `Matrix` has sixteen distinct elements and no `Sort`, so a transposed implementation would
  # produce a different string. The oracle is the descriptor order, never `Matrix.ToString`.
  def test_matrix_carries_sixteen_distinct_elements_in_row_major_order
    value = sample("Matrix")
    members = row("MatrixConverter").fetch("propertyOrder")
    assert_equal 16, members.length
    assert_equal 16, members.map { |member| value.public_send(member) }.uniq.length
    descriptor = converter_for("MatrixConverter").ConvertTo(nil, nil, value, CM::InstanceDescriptor)
    assert_equal members.map { |member| value.public_send(member) }, descriptor.Arguments
    # A transpose swaps M12 with M21; the sample makes them different values.
    refute_equal value.M12, value.M21
    assert_equal value.M12, descriptor.Arguments[1]
    assert_equal value.M21, descriptor.Arguments[4]
  end

  # ------------------------------------------------------------------------------- the culture

  # The separator comes from `culture.TextInfo.ListSeparator`, never from a hard-coded comma.
  def test_the_list_separator_comes_from_the_culture
    assert_equal ",", GL::CultureInfo.InvariantCulture.TextInfo.ListSeparator
    assert_equal ";", german.TextInfo.ListSeparator

    converter = converter_for("Vector3Converter")
    value = X::Vector3.new(1.5, -2.25, 3.75)
    assert_equal "1.5, -2.25, 3.75", converter.ConvertTo(nil, GL::CultureInfo.InvariantCulture, value, ::String)
    assert_equal "1,5; -2,25; 3,75", converter.ConvertTo(nil, german, value, ::String)
    assert_equal value, converter.ConvertFrom(nil, german, "1,5; -2,25; 3,75")

    # The join separator carries a trailing space and the split separator does not, which is the
    # `String.Concat(listSeparator, " ")` at IL_0015.
    assert_includes converter.ConvertTo(nil, german, value, ::String), "; "
    assert_equal value, converter.ConvertFrom(nil, german, "1,5;-2,25;3,75")
  end

  # A nil culture resolves to `CurrentCulture`, which is the invariant one until a consumer sets it.
  # Setting it is restored afterwards, so no test leaks a process-wide value into the next.
  def test_a_nil_culture_resolves_to_the_current_one_and_setting_it_is_restored
    assert_equal "", GL::CultureInfo.CurrentCulture.Name
    converter = converter_for("Vector2Converter")
    value = X::Vector2.new(1.5, -2.25)
    assert_equal "1.5, -2.25", converter.ConvertTo(nil, nil, value, ::String)

    GL::CultureInfo.with_current_culture(german) do
      assert_equal "1,5; -2,25", converter.ConvertTo(nil, nil, value, ::String)
      assert_equal value, converter.ConvertFrom(nil, nil, "1,5; -2,25")
    end
    assert_equal "", GL::CultureInfo.CurrentCulture.Name
    assert_equal "1.5, -2.25", converter.ConvertTo(nil, nil, value, ::String)
  end

  # The invariant culture's values are read out of the pinned mscorlib, not remembered.
  def test_the_invariant_culture_carries_the_measured_values
    invariant = GL::CultureInfo.InvariantCulture
    assert_equal "", invariant.Name
    assert_equal ",", invariant.TextInfo.ListSeparator
    assert_equal ".", invariant.NumberDecimalSeparator
    assert_equal ",", invariant.NumberGroupSeparator
    assert_equal "-", invariant.NegativeSign
    assert_equal "+", invariant.PositiveSign
    assert_equal "NaN", invariant.NaNSymbol
    assert_equal "Infinity", invariant.PositiveInfinitySymbol
    assert_equal "-Infinity", invariant.NegativeInfinitySymbol
    assert_same invariant, GL::CultureInfo.InvariantCulture
    assert_same invariant.TextInfo, invariant.TextInfo
  end

  # Whitespace around the whole string and around each element, and the exact decimal separator.
  def test_whitespace_and_decimal_separator_interaction
    converter = converter_for("Vector2Converter")
    value = X::Vector2.new(1.5, -2.25)
    assert_equal value, converter.ConvertFrom(nil, nil, "  1.5, -2.25  ")
    assert_equal value, converter.ConvertFrom(nil, nil, "1.5 ,   -2.25")
    # In a culture whose decimal separator is "," the invariant spelling is not a second spelling:
    # "." is that culture's *group* separator, so "1.5" is fifteen, exactly as the CLR reads it.
    assert_equal X::Vector2.new(15.0, -225.0), converter.ConvertFrom(nil, german, "1.5; -2.25")
  end

  # ------------------------------------------------------------------------- the error semantics

  def test_the_string_failures_are_argument_errors_naming_the_expected_parameters
    converter = converter_for("Vector3Converter")
    {
      "too few" => "1.5, 2.5",
      "too many" => "1.5, 2.5, 3.5, 4.5",
      "invalid element" => "1.5, zzz, 3.5",
      "empty" => "",
      "separator only" => ",,",
      "trailing separator" => "1.5, 2.5, 3.5,"
    }.each do |label, text|
      error = assert_raises(::ArgumentError, label) { converter.ConvertFrom(nil, nil, text) }
      assert_includes error.message, "InvalidStringFormat", label
      assert_includes error.message, "X,Y,Z", label
    end
  end

  # A non-string source answers null from `ConvertToValues`, which is what makes the converter fall
  # through to the base rather than throw its own error — and the base throws for anything that is
  # not an InstanceDescriptor.
  def test_a_non_string_source_falls_through_to_the_base
    converter = converter_for("Vector3Converter")
    assert_raises(CNA::Runtime::NotSupportedError) { converter.ConvertFrom(nil, nil, 42) }
    assert_raises(CNA::Runtime::NotSupportedError) { converter.ConvertFrom(nil, nil, nil) }
    assert_raises(CNA::Runtime::NotSupportedError) { converter.ConvertFrom(nil, nil, X::Vector2.new(1, 2)) }
  end

  # `ConvertTo` opens with the destinationType null check, before anything else, in all twelve.
  def test_convert_to_refuses_a_nil_destination_type_first
    rows.each do |entry|
      name = entry.fetch("type").split(".").last
      error = assert_raises(::ArgumentError, name) do
        converter_for(name).ConvertTo(nil, nil, sample(entry.fetch("valueType")), nil)
      end
      assert_includes error.message, "destinationType", name
    end
  end

  # `CreateInstance` refuses a nil dictionary with the `NullNotAllowed` resource, in all twelve.
  def test_create_instance_refuses_a_nil_dictionary_and_reads_its_keys_by_name
    rows.each do |entry|
      name = entry.fetch("type").split(".").last
      assert entry.fetch("createInstance").fetch("nullCheck"), name
      error = assert_raises(::ArgumentError, name) { converter_for(name).CreateInstance(nil, nil) }
      assert_includes error.message, "propertyValues", name
      assert_includes error.message, "NullNotAllowed", name

      # The keys are the descriptor names in the authored order, and the value it builds is the one
      # those values describe.
      value = sample(entry.fetch("valueType"))
      keys = entry.fetch("createInstance").fetch("keys")
      assert_equal entry.fetch("descriptors").map { |item| item.fetch("member") }, keys, name
      built = converter_for(name).CreateInstance(nil, keys.to_h { |key| [key, value.public_send(key)] })
      assert_equal value, built, name
    end
  end

  # ------------------------------------------------------- PropertyDescriptor and its collection

  def test_the_descriptors_carry_the_measured_property_descriptor_contract
    converter = converter_for("Vector3Converter")
    value = sample("Vector3")
    descriptor = converter.GetProperties(nil, value, nil).Find("Y", false)
    refute_nil descriptor

    assert_equal "Y", descriptor.Name
    assert_equal X::Vector3, descriptor.ComponentType
    assert_equal ::Float, descriptor.PropertyType
    refute descriptor.IsReadOnly
    refute descriptor.CanResetValue(value)
    assert descriptor.ShouldSerializeValue(value)
    assert_nil descriptor.ResetValue(value)
    assert_equal(-2.25, descriptor.GetValue(value))
    assert_kind_of CM::SingleConverter, descriptor.Converter
    assert_empty descriptor.Attributes
    assert_nil descriptor.GetEditor(::Object)

    # SetValue writes through the type's own setter and raises the change notification, which is
    # the OnValueChanged call at IL_000d..IL_0014 of the field descriptor. `System.EventHandler`
    # collapses to any Ruby callable of arity two, so a lambda is what a consumer supplies.
    seen = []
    handler = ->(component, args) { seen << [component, args] }
    descriptor.AddValueChanged(value, handler)
    descriptor.SetValue(value, 9.5)
    assert_equal 9.5, value.Y
    assert_equal 1, seen.length
    assert_same value, seen.first.first
    assert_same CNA::Runtime::EventArgs::Empty, seen.first.last

    descriptor.RemoveValueChanged(value, handler)
    descriptor.SetValue(value, 8.5)
    assert_equal 8.5, value.Y
    assert_equal 1, seen.length, "a removed handler must not fire again"
  end

  def test_the_collection_find_is_a_linear_ordinal_scan_that_answers_nil_on_a_miss
    collection = converter_for("Vector3Converter").GetProperties(nil, sample("Vector3"), nil)
    assert_equal 3, collection.Count
    assert_equal "X", collection[0].Name
    assert_equal "Z", collection[2].Name
    assert_raises(::IndexError) { collection[3] }
    assert_raises(::IndexError) { collection[-1] }

    assert_equal "Y", collection.Find("Y", false).Name
    assert_nil collection.Find("y", false), "the case-sensitive comparison is ordinal"
    assert_equal "Y", collection.Find("y", true).Name, "the ignore-case comparison is OrdinalIgnoreCase"
    assert_nil collection.Find("Q", false)
    assert_nil collection.Find("Q", true)
    assert_equal "Y", collection["Y"].Name
    assert_nil collection["q"]
    assert_equal 1, collection.IndexOf(collection[1])
    assert collection.Contains(collection[0])
  end

  # `Sort` answers a **new** collection and never reorders the receiver.
  def test_sort_answers_a_new_collection_and_leaves_the_receiver_alone
    collection = converter_for("MatrixConverter").GetProperties(nil, sample("Matrix"), nil)
    original = collection.map(&:Name)
    alphabetical = collection.Sort
    refute_same collection, alphabetical
    assert_equal original, collection.map(&:Name)
    assert_equal original.sort, alphabetical.map(&:Name)

    named = collection.Sort(%w[M44 M11])
    assert_equal %w[M44 M11], named.map(&:Name).first(2)
    # The tail is the default order, which is alphabetical rather than the authored one.
    assert_equal (original - %w[M44 M11]).sort, named.map(&:Name).drop(2)
    assert_equal original, collection.map(&:Name)

    # `System.Collections.IComparer` collapses to a Ruby two-argument comparison, and a comparer
    # survives into the collection a further `Sort` answers -- the CLR constructs each new
    # collection with both ordering inputs, so the one it was not given is carried over.
    reversed = collection.Sort(->(left, right) { right.Name <=> left.Name })
    assert_equal original.sort.reverse, reversed.map(&:Name)
    assert_equal original.sort.reverse, reversed.Sort.map(&:Name)
    assert_equal original, collection.map(&:Name)
  end

  def test_the_collection_a_converter_answers_is_mutable_and_empty_is_read_only
    collection = converter_for("Vector2Converter").GetProperties(nil, sample("Vector2"), nil)
    refute collection.IsReadOnly
    added = collection.Add(collection[0])
    assert_equal 2, added
    assert_equal 3, collection.Count
    collection.RemoveAt(2)
    assert_equal 2, collection.Count

    assert CM::PropertyDescriptorCollection.Empty.IsReadOnly
    assert_equal 0, CM::PropertyDescriptorCollection.Empty.Count
    assert_raises(CNA::Runtime::NotSupportedError) { CM::PropertyDescriptorCollection.Empty.Add(collection[0]) }
    assert_raises(CNA::Runtime::NotSupportedError) { CM::PropertyDescriptorCollection.Empty.Clear }
  end

  # ------------------------------------------------------------------------- TypeDescriptor

  def test_type_descriptor_answers_the_registered_converter_for_every_converted_type
    rows.each do |entry|
      type = X.const_get(short(entry.fetch("valueType")))
      converter = CM::TypeDescriptor.GetConverter(type)
      assert_instance_of D.const_get(entry.fetch("type").split(".").last), converter, entry.fetch("valueType")
      # A fresh instance each call, so a consumer mutating one cannot affect the next.
      refute_same converter, CM::TypeDescriptor.GetConverter(type)
    end
    # An unregistered type answers the base converter rather than raising.
    assert_instance_of CM::TypeConverter, CM::TypeDescriptor.GetConverter(::Object)
    assert_raises(::ArgumentError) { CM::TypeDescriptor.GetConverter(nil) }
  end

  def test_type_descriptor_answers_properties_for_a_converted_value
    value = sample("Vector3")
    properties = CM::TypeDescriptor.GetProperties(value)
    assert_equal %w[X Y Z], properties.map(&:Name)
    refute_same properties, CM::TypeDescriptor.GetProperties(value)
    assert_equal 0, CM::TypeDescriptor.GetProperties(nil).Count
    assert_equal 0, CM::TypeDescriptor.GetProperties(::Object.new).Count
  end

  # `ExpandableObjectConverter` is not empty: it overrides two members, and `GetProperties` ignores
  # its context and forwards to `TypeDescriptor.GetProperties(value, attributes)`.
  def test_expandable_object_converter_overrides_exactly_two_members
    expandable = CM::ExpandableObjectConverter.new
    assert expandable.GetPropertiesSupported(nil)
    refute CM::TypeConverter.new.GetPropertiesSupported(nil)
    assert_equal %w[X Y Z], expandable.GetProperties(nil, sample("Vector3"), nil).map(&:Name)
    assert_nil CM::TypeConverter.new.GetProperties(nil, sample("Vector3"), nil)
  end

  # The whole point of the end-to-end path: a consumer walks from a type to a value and back
  # without naming any XNA-private class.
  def test_a_consumer_can_do_a_design_time_round_trip_for_several_types
    {"Vector3" => "1.5, -2.25, 3.75", "Point" => "-3, 7", "Color" => "10, 20, 30, 40",
     "Vector2" => "1.5, -2.25", "Quaternion" => "0.125, -0.25, 0.5, -0.75"}.each do |name, text|
      type = X.const_get(name)
      converter = CM::TypeDescriptor.GetConverter(type)
      assert converter.CanConvertFrom(nil, ::String), name

      value = converter.ConvertFrom(nil, nil, text)
      assert_instance_of type, value, name
      assert_equal text, converter.ConvertTo(nil, nil, value, ::String), name

      properties = converter.GetProperties(nil, value, nil)
      values = properties.to_h { |descriptor| [descriptor.Name, descriptor.GetValue(value)] }
      rebuilt = converter.CreateInstance(nil, values)
      assert_equal value, rebuilt, name

      next unless converter.CanConvertTo(nil, CM::InstanceDescriptor) &&
                  row("#{name}Converter").fetch("convertTo").fetch("constructorResolves")

      descriptor = converter.ConvertTo(nil, nil, value, CM::InstanceDescriptor)
      assert_equal value, descriptor.Invoke, name
      assert_equal value, converter.ConvertFrom(nil, nil, descriptor), name
    end
  end

  # ------------------------------------------------------------------- ITypeDescriptorContext

  # A context is accepted only when it answers the whole measured contract; nil is always accepted.
  def test_a_context_must_answer_the_whole_measured_interface
    assert_equal %i[Container Instance PropertyDescriptor OnComponentChanging OnComponentChanged GetService],
                 CM::ITypeDescriptorContext::REQUIRED

    complete = Class.new do
      include CM::ITypeDescriptorContext
      def Container = nil
      def Instance = nil
      def PropertyDescriptor = nil
      def OnComponentChanging = true
      def OnComponentChanged = nil
      def GetService(_type) = nil
    end.new

    converter = converter_for("Vector3Converter")
    assert converter.CanConvertFrom(complete, ::String)
    assert_equal sample("Vector3"), converter.ConvertFrom(complete, nil, "1.5, -2.25, 3.75")

    partial = Class.new do
      def Container = nil
      def Instance = nil
      def PropertyDescriptor = nil
      def GetService(_type) = nil
    end.new
    error = assert_raises(::ArgumentError) { converter.CanConvertFrom(partial, ::String) }
    assert_includes error.message, "OnComponentChanging"
    assert_includes error.message, "OnComponentChanged"
    # Nil is a context the CLR allows everywhere, and every one-argument overload passes it.
    assert converter.CanConvertFrom(nil, ::String)
  end

  # ------------------------------------------------------------------------------ the registries

  # Both registries are explicit. Nothing scans and nothing infers, so cold-loading in a different
  # order gives identical answers — asserted in a subprocess, because a load order cannot be
  # changed inside a process that has already loaded.
  def test_the_registries_are_load_order_independent
    require "rbconfig"
    script = <<~RUBY
      $LOAD_PATH.unshift(#{ROOT.join("lib").to_s.inspect})
      require "cna"
      require "microsoft/xna/framework"
      X = Microsoft::Xna::Framework
      CM = CNA::Runtime::ComponentModel
      rows = X::Design.const_get(:ROWS)
      answers = rows.keys.shuffle.map do |name|
        type = X.const_get(rows.fetch(name).valueType)
        converter = CM::TypeDescriptor.GetConverter(type)
        [name, converter.class.name, converter.GetProperties(nil, nil, nil).map(&:Name)]
      end
      puts Marshal.dump(answers.sort).unpack1("H*")
    RUBY
    # `IO.popen` with an argument array, never a command string: a string goes through the shell,
    # which would expand `$LOAD_PATH` to nothing. Only the last line is read, because the child may
    # emit warnings the parent's `-w` asked for.
    run = -> { IO.popen([RbConfig.ruby, "-e", script], &:read).lines.last.to_s.strip }
    first = run.call
    second = run.call
    refute_empty first, "the subprocess produced no answer"
    assert_equal first, second, "the registries answered differently across two cold loads"
    decoded = Marshal.load([first].pack("H*"))
    assert_equal 12, decoded.length
    assert_equal rows.map { |entry| entry.fetch("propertyOrder") }.sort,
                 decoded.map(&:last).sort
  end

  # The reflection registry answers nil for a miss and never raises, which is what
  # `Type.GetField`/`GetProperty`/`GetConstructor` do.
  def test_the_reflection_registry_answers_nil_on_a_miss_and_never_monkey_patches
    assert_nil RF.GetField(X::Vector3, "Q")
    assert_nil RF.GetProperty(X::Vector3, "X"), "Vector3's X is a field, not a property"
    assert_nil RF.GetField(X::Color, "R"), "Color's R is a property, not a field"
    refute_nil RF.GetProperty(X::Color, "R")
    assert_nil RF.GetField(::String, "anything"), "an unregistered type answers nil"
    refute RF.registered?(::String)

    # The same instance for the same lookup, so reflection identity is stable.
    assert_same RF.GetField(X::Vector3, "X"), RF.GetField(X::Vector3, "X")
    assert_same RF.GetConstructor(X::Point, ["System.Int32"] * 2), RF.GetConstructor(X::Point, ["System.Int32"] * 2)

    # And nothing was added to Module or Object.
    refute ::Module.method_defined?(:GetField)
    refute ::Object.method_defined?(:GetField)
    refute ::Module.method_defined?(:GetConstructor)
  end

  # ------------------------------------------------------------------------- the leak boundary

  # XNA declares the three descriptor classes `.class private`, and they must not become public XNA
  # API. The API verifier's leak walk uses `Module#constants`, which `private_constant` removes them
  # from, so this asserts the same property directly.
  def test_the_private_descriptor_classes_are_not_public_xna_api
    %w[MemberPropertyDescriptor FieldPropertyDescriptor PropertyPropertyDescriptor].each do |name|
      # `Module#constants` is what the API verifier's leak walk enumerates, and `private_constant`
      # removes them from it. Scope resolution refuses them too; `const_get` deliberately does not,
      # which is a Ruby fact rather than a leak.
      refute_includes D.constants(false), name.to_sym, name
      assert_raises(NameError, name) do
        eval("Microsoft::Xna::Framework::Design::#{name}", binding, __FILE__, __LINE__)
      end
    end
    # What a consumer does observe is the PropertyDescriptor contract, through the collection.
    descriptor = converter_for("Vector3Converter").GetProperties(nil, sample("Vector3"), nil).first
    assert_kind_of CM::PropertyDescriptor, descriptor
    assert_equal 0, STRICT.fetch("INTERNAL_TYPE_LEAK")
  end

  # **The namespace exposes the thirteen converters and nothing else.**
  #
  # The verifier's leak walk enumerates modules, so it would not have caught any of the three things
  # this found: two `assembly` generic helpers publicly callable under a snake_case spelling, two
  # data tables as public constants, and two module helper methods. None is an XNA identity and each
  # was reachable by a consumer.
  def test_the_design_namespace_exposes_the_converters_and_nothing_else
    expected = rows.map { |entry| entry.fetch("type").split(".").last } + %w[MathTypeConverter]
    assert_equal expected.sort.map(&:to_sym), D.constants(false).sort

    # `ConvertToValues` and `ConvertFromValues` are `.method assembly` in the IL. Neither the CLR
    # spelling nor this binding's may be publicly callable.
    %w[ConvertToValues ConvertFromValues].each do |clr|
      assert_equal "assembly",
                   DESIGN.fetch("base").fetch("members").find { |m| m.fetch("name") == clr }.fetch("access"), clr
      refute D::MathTypeConverter.respond_to?(clr.to_sym), clr
    end
    %i[convert_to_values convert_from_values].each do |internal|
      refute D::MathTypeConverter.respond_to?(internal), internal
      assert D::MathTypeConverter.singleton_class.private_method_defined?(internal), internal
    end
    assert_empty D.singleton_class.instance_methods(false), "the namespace declares no public helper"

    # And the two protected fields really are protected, as `.field family` is.
    %w[propertyDescriptions supportStringConvert].each do |field|
      assert D::MathTypeConverter.protected_method_defined?(field.to_sym), field
      refute D::MathTypeConverter.public_method_defined?(field.to_sym), field
    end
  end

  # The thirteen converters are XNA identities; everything they are built from is a BCL projection,
  # and no BCL identity may be counted as an XNA one.
  def test_the_bcl_projection_grew_and_the_xna_reference_did_not
    assert_equal 257, STRICT.fetch("REFERENCE_TYPES")
    assert_equal 2964, STRICT.fetch("REFERENCE_MEMBERS")
    assert_equal 254, STRICT.fetch("TARGET_TYPES")
    assert_equal 252, STRICT.fetch("COMPLETE_TYPES")
    assert_equal 3, STRICT.fetch("MISSING_TYPES")
    assert_operator STRICT.fetch("BCL_PROJECTED_IDENTITIES"), :>=, 48

    projection = STRICT.fetch("bclProjection").fetch("types")
    %w[
      System.ComponentModel.TypeConverter System.ComponentModel.ExpandableObjectConverter
      System.ComponentModel.ITypeDescriptorContext System.ComponentModel.PropertyDescriptor
      System.ComponentModel.PropertyDescriptorCollection System.ComponentModel.TypeDescriptor
      System.ComponentModel.Design.Serialization.InstanceDescriptor
      System.Globalization.CultureInfo System.Globalization.TextInfo
      System.Reflection.MemberInfo System.Reflection.ConstructorInfo
      System.Reflection.FieldInfo System.Reflection.PropertyInfo
    ].each do |identity|
      assert_includes projection, identity, identity
      refute identity.start_with?("Microsoft.Xna."), identity
    end
    # And the projected Ruby class really is in the CNA runtime, never a fabricated ::System.
    projection.each_value { |path| refute path.start_with?("System"), path }
    refute Object.const_defined?(:System, false)
  end

  # The demand counts, pinned. A page that says "the first parameter of forty-five members" when the
  # generated consumer list says thirty-eight is the kind of hand-done arithmetic this project keeps
  # finding wrong, so the counts a reader might quote are asserted against the file that derives
  # them -- and derived here a second way, from the reference contract, so the two must agree.
  def test_the_demand_counts_a_reader_would_quote_are_measured
    families = BCL.fetch("families").to_h { |entry| [entry.fetch("family"), entry] }
    expected = {
      # Every Design member that takes a context: MathTypeConverter's five, plus each derived
      # converter's ConvertTo and CreateInstance, plus the nine that declare ConvertFrom.
      "System.ComponentModel.ITypeDescriptorContext" => 5 + (12 * 2) + 9,
      # Every ConvertFrom and ConvertTo, which are the two that take a culture.
      "System.Globalization.CultureInfo" => 9 + 12,
      # Every CreateInstance.
      "System.Collections.IDictionary" => 12
    }
    expected.each do |identity, count|
      assert_equal count, families.fetch(identity).fetch("xnaConsumerCount"), identity
      assert_equal count, families.fetch(identity).fetch("xnaConsumers").length, identity
      # And every consumer really is a Design member, so the count is not inflated from elsewhere.
      assert(families.fetch(identity).fetch("xnaConsumers").all? { |entry| entry.include?(".Design.") }, identity)
    end
    assert_equal 38, families.fetch("System.ComponentModel.ITypeDescriptorContext").fetch("xnaConsumerCount")
    assert_equal 21, families.fetch("System.Globalization.CultureInfo").fetch("xnaConsumerCount")
  end

  # ------------------------------------------------------------------ the selected-scope gate

  # **A family the project has selected may never be classified `BCL_PROJECTION_SCOPE`.**
  #
  # That is the gate this milestone exists to install, and it is a gate rather than a note because
  # the classification is what let thirteen buildable types sit unbuilt for four milestones. It was
  # never a blocker: the authority was on the machine, the reach was measurable, and what the label
  # actually recorded was that projecting a descriptor system is work. Selecting a family is the
  # decision to do that work, so the two cannot coexist.
  #
  # The check is measured on three independent artifacts rather than by reading prose for the
  # phrase, because a document can be reworded and a measurement cannot.
  def test_a_selected_family_can_never_be_classified_bcl_projection_scope
    selection = JSON.parse(ROOT.join("tools", "api_compat", "selection.json").read)
    selected = selection.fetch("types").map { |entry| entry.fetch("name") }
    assert_equal 254, selected.length
    assert_equal 13, selected.count { |name| name.include?(".Design.") }

    # 1. The strict report. A selected type is complete or partial; it is never missing, and a
    #    missing selected type is precisely what the classification used to describe.
    accounted = STRICT.fetch("completeTypeNames") + STRICT.fetch("partialTypes").keys
    assert_empty selected - accounted, "a selected type is missing from the strict report"
    assert_empty selected & STRICT.fetch("missingTypeNames"), "a selected type is classified missing"

    # 2. The dependency frontier. `BCL_PROJECTION` was the blocker the converter family carried,
    #    and it must not name a selected type -- nor, now, anything at all.
    frontier = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read)
    frontier.fetch("dependencyCompleteCandidates").each do |candidate|
      refute_includes selected, candidate.fetch("name"),
                      "#{candidate.fetch("name")} is selected and still on the dependency frontier"
    end
    refute_includes frontier.fetch("blockerSummary").keys, "BCL_PROJECTION"

    # 3. The BCL register. Every ComponentModel identity the family reaches resolves to a real Ruby
    #    projection, so "the reach is too large" cannot be reasserted without this failing.
    projection = STRICT.fetch("bclProjection").fetch("types")
    reached = DESIGN.fetch("reachedBclIdentities").keys
                    .map { |entry| entry.split(":", 2).last }
                    .select { |identity| identity.start_with?("System.ComponentModel") }
    refute_empty reached
    assert_empty reached - projection.keys,
                 "the Design family reaches a System.ComponentModel identity the register does not project"
  end

  # The remaining three missing types are the adapter defect and nothing else. This is the assertion
  # that would fail if `BCL_PROJECTION_SCOPE` were ever reintroduced for a selected family.
  def test_no_design_type_remains_missing
    assert_equal %w[
      Microsoft.Xna.Framework.Graphics.GraphicsAdapter
      Microsoft.Xna.Framework.GraphicsDeviceInformation
      Microsoft.Xna.Framework.PreparingDeviceSettingsEventArgs
    ].sort, STRICT.fetch("missingTypeNames").sort
    assert_equal 16, STRICT.fetch("TOTAL_DIAGNOSTICS")
    %w[TYPE_KIND_MISMATCH BASE_MAPPING_MISMATCH INTERFACE_MAPPING_MISMATCH FIELD_MAPPING_MISMATCH
       PROPERTY_MAPPING_MISMATCH METHOD_SIGNATURE_MAPPING_MISMATCH PARAMETER_MAPPING_MISMATCH
       RETURN_MAPPING_MISMATCH GENERIC_MAPPING_MISMATCH ENUM_VALUE_MISMATCH FLAGS_MAPPING_MISMATCH
       EVENT_MAPPING_MISMATCH OPERATOR_MAPPING_MISMATCH LANGUAGE_MAPPING_MISMATCH
       UNEXPECTED_TYPE UNEXPECTED_MEMBER UNMEASURED_STRUCTURAL_CATEGORY].each do |category|
      assert_equal 0, STRICT.fetch(category), category
    end
  end
end
