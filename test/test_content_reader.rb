# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require "tmpdir"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# The `ContentReader` family — `ContentReader`, `ContentTypeReader`, `ContentTypeReader`1` and
# `ContentTypeReaderManager` — and the one BCL register decision behind it.
#
# `ContentReader` extends `System.IO.BinaryReader`, which the XNA 4.0 Windows reference contract
# names **exactly once** and exactly there. That is what admits the family to the BCL inventory,
# whose rule is that a family with no XNA consumer is refused; it is also why two of
# `BinaryReader`'s twenty-six public identities are not projected, since `System.Decimal` and
# `System.Text.Encoding` have no XNA consumer at all.
#
# Everything else is derived from the pinned Microsoft IL: the container header's four refusals, the
# type manifest, the one-based type identifier, the shared-resource fixups, the external-reference
# path and the four rules `InvokeReader` applies. This test drives all of it against a compiled
# asset it builds itself, byte by byte, so what is asserted is a real load rather than a shape.
class ContentReaderTest < Minitest::Test
  F = Microsoft::Xna::Framework
  C = Microsoft::Xna::Framework::Content
  R = CNA::Runtime::ContentTypeReaderRegistry
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  BCL = JSON.parse(ROOT.join("docs", "generated", "bcl-inventory.json").read).freeze

  NAMES = %w[ContentReader ContentTypeReader ContentTypeReader`1 ContentTypeReaderManager].freeze

  def setup
    @registry = [R.factories.dup, R.name_to_reader.dup, R.target_type_to_reader.dup,
                 R.reader_type_to_reader.dup]
    R.clear
  end

  def teardown
    R.clear
    R.factories.merge!(@registry[0])
    R.name_to_reader.merge!(@registry[1])
    R.target_type_to_reader.merge!(@registry[2])
    R.reader_type_to_reader.merge!(@registry[3])
  end

  # ------------------------------------------------------------------- the contract, from metadata

  def test_all_four_are_complete_and_the_missing_inventory_fell
    NAMES.each do |short|
      assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.Content.#{short}"
    end
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_equal ReviewedScoreboard::MISSING_TYPES, STRICT.fetch("MISSING_TYPES")
    assert_empty STRICT.fetch("missingTypeNames").grep(/\AMicrosoft\.Xna\.Framework\.Content\./)
    assert_equal 0, STRICT.fetch("UNEXPECTED_MEMBER")
    assert_equal 0, STRICT.fetch("INTERNAL_TYPE_LEAK")
  end

  # The whole reason this family needed a register decision, stated as the measurement that makes it
  # one: the reference contract names `System.IO.BinaryReader` once, as this type's base.
  def test_binary_reader_is_named_once_and_that_is_what_admits_it
    named = REFERENCE.values.flat_map do |type|
      values = [type["baseType"]]
      type.fetch("members").each do |member|
        values << member["type"] << member["returnType"]
        values.concat(member.fetch("parameters", []).map { |parameter| parameter["type"] })
      end
      values.compact.map { |value| [type.fetch("name"), value] }
    end.select { |_, value| value.include?("BinaryReader") }
    assert_equal [["Microsoft.Xna.Framework.Content.ContentReader", "System.IO.BinaryReader"]], named

    assert_equal "CNA::Runtime::BinaryReader",
                 CNA::Runtime::BclProjection::TYPES.fetch("System.IO.BinaryReader")
    assert_equal CNA::Runtime::BinaryReader, C::ContentReader.superclass
    assert_equal ReviewedScoreboard::BCL_PROJECTED_IDENTITIES, STRICT.fetch("BCL_PROJECTED_IDENTITIES")
    family = BCL.fetch("families").find { |entry| entry.fetch("family") == "System.IO.BinaryReader" }
    assert_equal "direct", family.fetch("demand")
  end

  # The two identities that are measured and deliberately not projected, with the rule that refuses
  # them rather than a preference: the inventory admits a family only when the contract names it.
  def test_the_two_unprojected_binary_reader_members_are_refused_by_the_inventorys_own_rule
    measured = BCL.fetch("types").fetch("System.IO.BinaryReader").fetch("members")
                  .select { |member| member.fetch("access") == "public" }
    assert_equal 26, measured.length

    refute CNA::Runtime::BinaryReader.public_method_defined?(:ReadDecimal)
    decimal = measured.find { |member| member.fetch("name") == "ReadDecimal" }
    assert_equal "valuetype System.Decimal", decimal.fetch("returnType")
    encoding = measured.select { |member| member.fetch("name") == ".ctor" }
                       .find { |member| member.fetch("parameters").length == 2 }
    assert_equal "class System.Text.Encoding", encoding.fetch("parameters").last.fetch("type")

    # Neither type is a family, and neither could be: nothing in the reference contract names one.
    families = BCL.fetch("families").map { |entry| entry.fetch("family") }
    refute_includes families, "System.Decimal"
    refute_includes families, "System.Text.Encoding"
    named = REFERENCE.values.flat_map { |type| JSON.generate(type) }.join
    refute_includes named, "System.Decimal"
    refute_includes named, "System.Text.Encoding"
    # And the one-argument constructor, which is the one XNA's own IL calls, is projected.
    assert_equal 1, CNA::Runtime::BinaryReader.instance_method(:initialize).arity
  end

  def test_neither_the_reader_nor_the_manager_can_be_constructed
    %w[ContentReader ContentTypeReaderManager].each do |short|
      type = C.const_get(short, false)
      assert_raises(NoMethodError, short) { type.new }
      assert_empty REFERENCE.fetch("Microsoft.Xna.Framework.Content.#{short}")
                            .fetch("members").select { |member| member.fetch("kind") == "constructor" }
    end
    # The manager's whole public surface is one method, which is why a consumer only ever sees one
    # inside `Initialize`.
    assert_equal %i[GetTypeReader], C::ContentTypeReaderManager.public_instance_methods(false).sort
  end

  # ----------------------------------------------------------------------------- the base reader

  def reader_over(bytes) = CNA::Runtime::BinaryReader.new(CNA::Runtime::Stream.over_bytes(bytes.b))

  def test_every_projected_primitive_reads_little_endian
    bytes = [1].pack("C") + [0].pack("C") + [-3].pack("c") + [0xFE].pack("C") +
            [-2].pack("s<") + [0xFFFE].pack("v") + [-70_000].pack("l<") + [4_000_000_000].pack("V") +
            [-5_000_000_000].pack("q<") + [18_000_000_000_000_000_000].pack("Q<") +
            [0.5].pack("e") + [-0.25].pack("E")
    reader = reader_over(bytes)
    assert_equal true, reader.ReadBoolean
    assert_equal false, reader.ReadBoolean
    assert_equal(-3, reader.ReadSByte)
    assert_equal 0xFE, reader.ReadByte
    assert_equal(-2, reader.ReadInt16)
    assert_equal 0xFFFE, reader.ReadUInt16
    assert_equal(-70_000, reader.ReadInt32)
    assert_equal 4_000_000_000, reader.ReadUInt32
    assert_equal(-5_000_000_000, reader.ReadInt64)
    assert_equal 18_000_000_000_000_000_000, reader.ReadUInt64
    assert_in_delta 0.5, reader.ReadSingle, 0.0
    assert_in_delta(-0.25, reader.ReadDouble, 0.0)
    assert_raises(EOFError) { reader.ReadByte }
  end

  # A 7-bit-encoded byte count and then the bytes. The count is what makes a two-byte length
  # possible, so a string longer than 127 bytes is the case that proves the encoding is read.
  def test_read_string_reads_a_seven_bit_length_and_the_bytes
    long = "x" * 200
    reader = reader_over(seven_bit(5) + "hello" + seven_bit(0) + seven_bit(long.bytesize) + long)
    assert_equal "hello", reader.ReadString
    assert_equal Encoding::UTF_8, reader.ReadString.encoding
    assert_equal long, reader.ReadString
  end

  def test_bytes_chars_and_the_three_argument_reads
    reader = reader_over("abcdef")
    assert_equal "abc", reader.ReadBytes(3)
    assert_equal [100, 101], reader.ReadChars(2)
    # Short at the end of the stream rather than raising, which is the CLR's contract for both.
    assert_equal "f", reader.ReadBytes(4)
    assert_empty reader.ReadChars(2)

    buffer = +"\0\0\0\0".b
    into = reader_over("wxyz")
    assert_equal 2, into.Read(buffer, 1, 2)
    assert_equal "\0wx\0".b, buffer
    units = [0, 0, 0]
    assert_equal 2, into.Read(units, 0, 2)
    assert_equal [121, 122, 0], units
    assert_raises(ArgumentError) { into.Read(buffer, 0, 99) }
    assert_raises(TypeError) { into.Read(Object.new, 0, 1) }
  end

  # `Read()` answers -1 at the end and consumes; `PeekChar` answers -1 there too and consumes
  # nothing. A multi-byte UTF-8 character is one code unit either way.
  def test_read_and_peek_agree_and_peek_does_not_advance
    reader = reader_over("Aé")
    assert_equal 65, reader.PeekChar
    assert_equal 65, reader.Read
    assert_equal 0xE9, reader.PeekChar
    assert_equal 0xE9, reader.ReadChar
    assert_equal(-1, reader.PeekChar)
    assert_equal(-1, reader.Read)
    assert_raises(EOFError) { reader.ReadChar }
  end

  def test_the_base_stream_is_the_one_given_and_closing_is_idempotent
    stream = CNA::Runtime::Stream.over_bytes("ab".b)
    reader = CNA::Runtime::BinaryReader.new(stream)
    assert_same stream, reader.BaseStream
    reader.Close
    reader.Dispose
    assert_raises(CNA::DisposedObjectError) { reader.ReadByte }
    assert_raises(CNA::DisposedObjectError) { reader.BaseStream }
    assert_raises(ArgumentError) { CNA::Runtime::BinaryReader.new(nil) }
    assert_raises(TypeError) { CNA::Runtime::BinaryReader.new("not a stream") }
  end

  # ------------------------------------------------------------------------- the value-type reads

  # `ReadSingle` and `ReadDouble` are `virtual` overrides that read an integer and reinterpret its
  # bits rather than calling the base. That is the same bytes in the same order on this host, and it
  # is asserted by comparing the two paths on one buffer rather than by reasoning about it.
  def test_the_single_and_double_overrides_agree_with_the_base_bit_for_bit
    values = [0.0, -0.0, 1.0, -2.5, 3.4028235e38, 1.1754944e-38]
    bytes = values.pack("e*")
    base = reader_over(bytes)
    override = content_reader_over(bytes)
    values.length.times { assert_equal base.ReadSingle, override.ReadSingle }

    doubles = [0.0, -1.5, 1.7976931348623157e308]
    base = reader_over(doubles.pack("E*"))
    override = content_reader_over(doubles.pack("E*"))
    doubles.length.times { assert_equal base.ReadDouble, override.ReadDouble }
  end

  def test_the_composite_reads_are_the_ils_own_call_sequences
    reader = content_reader_over([1.0, 2.0].pack("e*") + [3.0, 4.0, 5.0].pack("e*") +
                                 [6.0, 7.0, 8.0, 9.0].pack("e*") + [10.0, 11.0, 12.0, 13.0].pack("e*") +
                                 (1..16).map(&:to_f).pack("e*") + [0x44332211].pack("V"))
    assert_equal F::Vector2.new(1.0, 2.0), reader.ReadVector2
    assert_equal F::Vector3.new(3.0, 4.0, 5.0), reader.ReadVector3
    assert_equal F::Vector4.new(6.0, 7.0, 8.0, 9.0), reader.ReadVector4
    # X, Y, Z, W -- the order the IL sets the four fields in.
    quaternion = reader.ReadQuaternion
    assert_equal [10.0, 11.0, 12.0, 13.0], [quaternion.X, quaternion.Y, quaternion.Z, quaternion.W]
    # Sixteen singles in row order, M11 first and M44 last.
    matrix = reader.ReadMatrix
    assert_equal 1.0, matrix.M11
    assert_equal 4.0, matrix.M14
    assert_equal 5.0, matrix.M21
    assert_equal 16.0, matrix.M44
    # One ReadUInt32 straight into PackedValue, so the byte order is the packed one.
    assert_equal 0x44332211, reader.ReadColor.PackedValue
  end

  # ------------------------------------------------------------------------------ the container

  def test_the_header_refuses_four_ways_and_says_which
    {"XNC" => /does not begin with XNB/,
     :platform => /another platform/,
     :version => /container version/,
     :compressed => /LZX-compressed/,
     :size => /declares \d+ bytes/}.each do |kind, message|
      bytes =
        case kind
        when "XNC" then "XNC".b + [0x77, 5, 0].pack("CvC")
        when :platform then "XNB".b + [0x6D].pack("C") + [5].pack("v") + [10].pack("l<")
        when :version then "XNB".b + [0x77].pack("C") + [4].pack("v") + [10].pack("l<")
        when :compressed then "XNB".b + [0x77].pack("C") + [0x8005].pack("v") + [14].pack("l<")
        when :size then "XNB".b + [0x77].pack("C") + [5].pack("v") + [4096].pack("l<")
        end
      error = assert_raises(C::ContentLoadException, kind.to_s) { content_reader_over_raw(bytes) }
      assert_match message, error.message
    end
  end

  # The profile bits live in the version word and are masked out before the comparison, so a HiDef
  # asset -- profile 1 -- is the same container version as a Reach one and is accepted.
  def test_the_graphics_profile_bits_are_masked_out_of_the_version
    %w[0x0005 0x0105].each do |literal|
      bytes = "XNB".b + [0x77].pack("C") + [Integer(literal, 16)].pack("v") + [10].pack("l<")
      content_reader_over_raw(bytes)
    end
  end

  # ---------------------------------------------------------------------------- end to end

  class PointReader < C::ContentTypeReaderOfT
    reads F::Point

    def Read(input, _existingInstance)
      F::Point.new(input.ReadInt32, input.ReadInt32)
    end
  end

  class VersionedReader < C::ContentTypeReaderOfT
    reads F::Rectangle

    def TypeVersion = 3
    def Read(_input, _existingInstance) = F::Rectangle.new(0, 0, 0, 0)
  end

  class NamedReader < C::ContentTypeReader
    def initialize = super(::String)
    def Read(input, _existingInstance) = input.ReadString
  end

  # A compiled asset this test wrote, read by a reader this test registered, through the public
  # `ContentManager.Load`. Nothing in the path is stubbed: the bytes are on disk, `OpenStream`
  # answers them through CNA's own title reader, and the manifest, the type identifier and the
  # object all come off the same reader.
  def test_a_compiled_asset_loads_end_to_end_and_is_cached
    R.register("Test.PointReader") { PointReader.new }
    with_asset("point", manifest: [["Test.PointReader", 0]],
                        payload: seven_bit(1) + [7, -9].pack("l<l<")) do |manager|
      point = manager.Load(F::Point, "point")
      assert_equal F::Point.new(7, -9), point
      # XNA's cache is the manager's, keyed on the clean path, and answers the same object.
      assert_same point, manager.Load(F::Point, "point")
      assert_same point, manager.Load(F::Point, "./point")
      manager.Unload
      refute_same point, manager.Load(F::Point, "point")
    end
  end

  # `ReadAsset` is the hook `OpenStream` was always meant to feed, and for the XNB path it really
  # does: the reader is built over the stream that member answers.
  def test_the_xnb_path_goes_through_open_stream_and_an_override_redirects_it
    R.register("Test.PointReader") { PointReader.new }
    redirected = Class.new(C::ContentManager) do
      attr_reader :asked

      def OpenStream(assetName)
        @asked = assetName
        super("point")
      end
    end
    with_asset("point", manifest: [["Test.PointReader", 0]],
                        payload: seven_bit(1) + [1, 2].pack("l<l<"),
                        manager_class: redirected) do |manager|
      assert_equal F::Point.new(1, 2), manager.Load(F::Point, "elsewhere")
      assert_equal "elsewhere", manager.asked
    end
  end

  # The manifest's version check, and the rollback that follows a failure: the reader the failed
  # manifest added is not left in the process-wide caches for the next load to find.
  def test_a_version_mismatch_fails_the_load_and_rolls_the_reader_back_out
    R.register("Test.VersionedReader") { VersionedReader.new }
    with_asset("versioned", manifest: [["Test.VersionedReader", 1]], payload: seven_bit(0)) do |manager|
      error = assert_raises(C::ContentLoadException) { manager.Load(F::Rectangle, "versioned") }
      assert_match(/compiled as version 1 and this reader is version 3/, error.message)
    end
    assert_empty R.name_to_reader
    assert_empty R.target_type_to_reader
    assert R.registered?("Test.VersionedReader"), "the registration survives; only the instance goes"
  end

  def test_an_unregistered_reader_name_names_itself
    with_asset("unknown", manifest: [["Test.NothingReader", 0]], payload: seven_bit(0)) do |manager|
      error = assert_raises(C::ContentLoadException) { manager.Load(F::Point, "unknown") }
      assert_match(/no ContentTypeReader is registered for "Test.NothingReader"/, error.message)
    end
  end

  # Two reader names claiming one target type is the manifest's own refusal, measured in
  # `AddTypeReader` as `FrameworkResources.TypeReaderDuplicate`.
  def test_two_readers_claiming_one_target_type_is_refused
    R.register("Test.PointReader") { PointReader.new }
    R.register("Test.OtherPointReader") { PointReader.new }
    with_asset("dup", manifest: [["Test.PointReader", 0], ["Test.OtherPointReader", 0]],
                      payload: seven_bit(0)) do |manager|
      error = assert_raises(C::ContentLoadException) { manager.Load(F::Point, "dup") }
      assert_match(/already reads/, error.message)
    end
  end

  # The type identifier is one-based, so zero is the null object and nothing else indexes anything.
  def test_the_type_identifier_is_one_based_and_zero_is_null
    R.register("Test.PointReader") { PointReader.new }
    with_asset("null", manifest: [["Test.PointReader", 0]], payload: seven_bit(0)) do |manager|
      assert_nil manager.Load(F::Point, "null")
    end
    R.clear
    R.register("Test.PointReader") { PointReader.new }
    with_asset("high", manifest: [["Test.PointReader", 0]], payload: seven_bit(9)) do |manager|
      error = assert_raises(C::ContentLoadException) { manager.Load(F::Point, "high") }
      assert_match(/names type reader 9, and its manifest declares 1/, error.message)
    end
  end

  # ------------------------------------------------------------------------- the reader contract

  def test_a_type_reader_defaults_to_version_zero_and_refuses_to_deserialize_in_place
    reader = NamedReader.new
    assert_equal ::String, reader.TargetType
    assert_equal 0, reader.TypeVersion
    assert_equal false, reader.CanDeserializeIntoExistingObject
    assert_nil reader.Initialize(nil)
    # A null target type is allowed: the IL guards only the IsValueType probe with it.
    permissive = Class.new(C::ContentTypeReader) { def initialize = super(nil) }.new
    assert_nil permissive.TargetType
    # And the abstract half really is abstract.
    abstract = Class.new(C::ContentTypeReader) { def initialize = super(::Object) }.new
    assert_raises(NotImplementedError) { abstract.Read(nil, nil) }
    generic = Class.new(C::ContentTypeReaderOfT) { reads ::Object }.new
    assert_raises(NotImplementedError) { generic.Read(nil, nil) }
  end

  # `ContentTypeReader`1`'s constructor is `ldtoken !T`, so a Ruby subclass that declares no target
  # type has no `!T` to load and says so.
  def test_the_generic_subclass_needs_its_type_argument
    error = assert_raises(ArgumentError) { Class.new(C::ContentTypeReaderOfT).new }
    assert_match(/must declare its target type/, error.message)
    assert_equal ["Microsoft::Xna::Framework::Point"], PointReader.clr_element_types
    assert_equal F::Point, PointReader.reads
  end

  # `GetTypeReader(Type)` refuses null first and answers only what the manifest registered.
  def test_the_manager_answers_only_registered_target_types
    R.register("Test.PointReader") { PointReader.new }
    R.register("Test.NamedReader") { NamedReader.new }
    seen = nil
    watcher = Class.new(C::ContentTypeReaderOfT) do
      reads F::Vector2
      define_method(:Initialize) { |manager| seen = manager }
      def Read(input, _existing) = input.ReadVector2
    end
    R.register("Test.WatcherReader") { watcher.new }
    with_asset("watched",
               manifest: [["Test.WatcherReader", 0], ["Test.PointReader", 0]],
               payload: seven_bit(1) + [1.0, 2.0].pack("e*")) do |manager|
      assert_equal F::Vector2.new(1.0, 2.0), manager.Load(F::Vector2, "watched")
    end
    assert_instance_of C::ContentTypeReaderManager, seen
    assert_same R.name_to_reader.fetch("Test.PointReader"), seen.GetTypeReader(F::Point)
    assert_raises(ArgumentError) { seen.GetTypeReader(nil) }
    assert_raises(C::ContentLoadException) { seen.GetTypeReader(F::Matrix) }
  end

  # ------------------------------------------------------------------------ the InvokeReader rules

  class InPlaceReader < C::ContentTypeReaderOfT
    reads F::Vector2
    def CanDeserializeIntoExistingObject = true
    def Read(input, existingInstance)
      return F::Vector2.new(input.ReadSingle, input.ReadSingle) if existingInstance.nil?

      existingInstance
    end
  end

  class ReplacingReader < C::ContentTypeReaderOfT
    reads F::Vector3
    def Read(input, _existingInstance) = F::Vector3.new(input.ReadSingle, 0.0, 0.0)
  end

  # Rule 2: a reader handed an instance to fill that answers a different object is
  # `InvalidOperationException(ReaderConstructedNewInstance)`, which this binding raises as
  # RuntimeError -- the register's pairing for that CLR type.
  def test_a_reader_that_replaces_the_instance_it_was_given_is_refused
    R.register("Test.InPlace") { InPlaceReader.new }
    R.register("Test.Replacing") { ReplacingReader.new }
    with_asset("inplace", manifest: [["Test.InPlace", 0]],
                          payload: seven_bit(1) + [1.0, 2.0].pack("e*")) do |manager|
      reader = compiled_reader(manager, "inplace")
      begin
        reader.__send__(:read_header)
        existing = F::Vector2.new(9.0, 9.0)
        assert_same existing, reader.ReadObject(F::Vector2, existing)
      ensure
        reader.Close
      end
    end
    with_asset("replacing", manifest: [["Test.Replacing", 0]],
                            payload: seven_bit(1) + [1.0].pack("e")) do |manager|
      reader = compiled_reader(manager, "replacing")
      begin
        reader.__send__(:read_header)
        error = assert_raises(RuntimeError) { reader.ReadObject(F::Vector3, F::Vector3.new(0, 0, 0)) }
        assert_match(/constructed a new instance/, error.message)
      ensure
        reader.Close
      end
    end
  end

  # Rule 1's other half: a plain `ContentTypeReader` answering the wrong type is `BadXnbWrongType`.
  def test_an_untyped_reader_answering_the_wrong_type_is_refused
    R.register("Test.NamedReader") { NamedReader.new }
    with_asset("wrong", manifest: [["Test.NamedReader", 0]],
                        payload: seven_bit(1) + seven_bit(2) + "hi") do |manager|
      error = assert_raises(C::ContentLoadException) { manager.Load(F::Point, "wrong") }
      assert_match(/holds a String where a .*Point was expected/, error.message)
    end
  end

  # `ReadRawObject` reads **no** type identifier, which is the whole of what "raw" means: the same
  # payload read the two ways differs by exactly the one byte the tag occupies.
  def test_read_raw_object_reads_no_type_identifier
    R.register("Test.PointReader") { PointReader.new }
    with_asset("raw", manifest: [["Test.PointReader", 0]],
                      payload: [4, 5].pack("l<l<")) do |manager|
      reader = compiled_reader(manager, "raw")
      begin
        reader.__send__(:read_header)
        assert_equal F::Point.new(4, 5), reader.ReadRawObject(F::Point)
      ensure
        reader.Close
      end
    end
  end

  class DisposableAsset
    attr_reader :disposed

    def initialize = (@disposed = false)
    def Dispose = (@disposed = true)
  end

  class DisposableReader < C::ContentTypeReaderOfT
    reads DisposableAsset
    def Read(_input, _existingInstance) = DisposableAsset.new
  end

  # Rules 3 and 4. A reference-type result that is disposable is recorded, and a supplied callable
  # **replaces** this manager's own bookkeeping rather than adding to it -- the IL is an if/else,
  # not two calls. A value-type target is never recorded however disposable it looks, which is the
  # `TargetIsValueType` branch `ContentTypeReader`'s `assembly` field decides.
  def test_a_disposable_asset_is_recorded_once_and_the_callable_replaces_the_default
    R.register("Test.DisposableReader") { DisposableReader.new }
    with_asset("disposable", manifest: [["Test.DisposableReader", 0]],
                             payload: seven_bit(1)) do |manager|
      asset = manager.Load(DisposableAsset, "disposable")
      refute asset.disposed
      manager.Unload
      assert asset.disposed, "the manager disposed what it recorded"
    end

    recorded = []
    with_asset("disposable", manifest: [["Test.DisposableReader", 0]],
                             payload: seven_bit(1)) do |manager|
      asset = manager.__send__(:ReadAsset, DisposableAsset, "disposable", ->(value) { recorded << value })
      assert_equal [asset], recorded
      manager.Unload
      refute asset.disposed, "the callable replaced the manager's list rather than adding to it"
    end
  end

  # A value type's reader never records, so `Unload` never touches it. `Point` is one, and this is
  # the branch that tells `TargetIsValueType` apart from `IDisposable`.
  def test_a_value_type_target_is_never_recorded
    R.register("Test.PointReader") { PointReader.new }
    with_asset("point", manifest: [["Test.PointReader", 0]],
                        payload: seven_bit(1) + [1, 2].pack("l<l<")) do |manager|
      manager.Load(F::Point, "point")
      assert_empty manager.instance_variable_get(:@disposable_assets)
      assert PointReader.new.__send__(:target_is_value_type?), "Point is a CLR value type"
      refute NamedReader.new.__send__(:target_is_value_type?), "String is not"
    end
  end

  # ----------------------------------------------------------------------- shared resources

  class HolderReader < C::ContentTypeReaderOfT
    reads ::Array

    def Read(input, _existingInstance)
      holder = []
      input.ReadSharedResource(F::Point) { |value| holder << value }
      holder
    end
  end

  # A shared resource is read once, after the primary object, and every place that named it is
  # patched afterwards. So the fixup has not run when `Read` returns and has run when `Load` does.
  def test_a_shared_resource_is_read_after_the_primary_object_and_patched_in
    R.register("Test.HolderReader") { HolderReader.new }
    R.register("Test.PointReader") { PointReader.new }
    payload = seven_bit(1) + seven_bit(1) + seven_bit(2) + [3, 4].pack("l<l<")
    with_asset("shared", manifest: [["Test.HolderReader", 0], ["Test.PointReader", 0]],
                         payload: payload, shared: 1) do |manager|
      holder = manager.Load(::Array, "shared")
      assert_equal [F::Point.new(3, 4)], holder
    end
  end

  # Index 0 is the null shared resource and records nothing at all, so the fixup never runs.
  def test_shared_resource_zero_records_nothing
    ran = false
    reader_class = Class.new(C::ContentTypeReaderOfT) do
      reads ::Array
      define_method(:Read) do |input, _existing|
        input.ReadSharedResource(F::Point) { ran = true }
        []
      end
    end
    R.register("Test.NullShared") { reader_class.new }
    # The primary object, its shared-resource index of zero, and then the one shared object the
    # header declared -- itself null. A declared shared resource is always read, whether or not
    # anything referenced it, which is why the trailing tag has to be there.
    with_asset("nullshared", manifest: [["Test.NullShared", 0]],
                             payload: seven_bit(1) + seven_bit(0) + seven_bit(0), shared: 1) do |manager|
      assert_empty manager.Load(::Array, "nullshared")
    end
    refute ran, "the null shared resource ran a fixup"
  end

  def test_a_shared_resource_index_beyond_the_declared_count_is_refused
    R.register("Test.HolderReader") { HolderReader.new }
    with_asset("badshared", manifest: [["Test.HolderReader", 0]],
                            payload: seven_bit(1) + seven_bit(4), shared: 1) do |manager|
      error = assert_raises(C::ContentLoadException) { manager.Load(::Array, "badshared") }
      assert_match(/names shared resource 4/, error.message)
    end
  end

  # ------------------------------------------------------------------- external references

  # It reads an Array rather than a Point so that the two readers in the same manifest claim two
  # target types, which is the manifest's own rule and not this test's convenience.
  class ReferenceReader < C::ContentTypeReaderOfT
    reads ::Array
    def Read(input, _existingInstance) = [input.ReadExternalReference(F::Point)]
  end

  # An empty reference is null; a non-empty one is resolved against the **asset's** directory and
  # loaded through the same manager, so it is an ordinary `Load` with a computed name.
  def test_an_external_reference_loads_through_the_same_manager
    R.register("Test.PointReader") { PointReader.new }
    R.register("Test.ReferenceReader") { ReferenceReader.new }
    Dir.mktmpdir("cna-content-reader") do |directory|
      write_asset(directory, "target", [["Test.PointReader", 0]], seven_bit(1) + [8, 6].pack("l<l<"), 0)
      write_asset(directory, "holder", [["Test.ReferenceReader", 0]],
                  seven_bit(1) + xnb_string("target"), 0)
      write_asset(directory, "empty", [["Test.ReferenceReader", 0]],
                  seven_bit(1) + xnb_string(""), 0)
      in_game do
        manager = C::ContentManager.new(F::GameServiceContainer.new, directory)
        assert_equal [F::Point.new(8, 6)], manager.Load(::Array, "holder")
        assert_equal [nil], manager.Load(::Array, "empty")
      end
    end
  end

  # ------------------------------------------------------------------------------- helpers

  private

  class HostGame < F::Game
    attr_reader :error

    def initialize(&body)
      @body = body
      super()
    end

    def Update(_gameTime)
      @body.call
    rescue ::Exception => e # rubocop:disable Lint/RescueException
      @error = e
    ensure
      self.Exit
    end
  end

  def in_game
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = HostGame.new { yield }
    begin
      game.Run
      raise game.error if game.error
    ensure
      game.Dispose
    end
  end

  def seven_bit(value)
    out = +"".b
    remaining = value
    loop do
      byte = remaining & 0x7F
      remaining >>= 7
      if remaining.zero?
        out << byte
        break
      end
      out << (byte | 0x80)
    end
    out
  end

  def xnb_string(text)
    bytes = text.b
    seven_bit(bytes.bytesize) + bytes
  end

  def xnb(manifest, payload, shared)
    body = seven_bit(manifest.length)
    manifest.each { |name, version| body << xnb_string(name) << [version].pack("l<") }
    body << seven_bit(shared)
    body << payload
    prologue = "XNB".b + [0x77].pack("C") + [5].pack("v")
    prologue + [prologue.bytesize + 4 + body.bytesize].pack("l<") + body
  end

  def write_asset(directory, name, manifest, payload, shared)
    File.binwrite(File.join(directory, "#{name}.xnb"), xnb(manifest, payload, shared))
  end

  def with_asset(name, manifest:, payload:, shared: 0, manager_class: C::ContentManager)
    Dir.mktmpdir("cna-content-reader") do |directory|
      write_asset(directory, name, manifest, payload, shared)
      in_game do
        yield manager_class.new(F::GameServiceContainer.new, directory)
      end
    end
  end

  def compiled_reader(manager, name)
    # `OpenStream` is protected on a manager, so the one caller that reaches it is this one.
    C::ContentReader.__send__(:create, manager, manager.__send__(:OpenStream, name), name, nil)
  end

  def content_reader_over(bytes)
    stream = CNA::Runtime::Stream.over_bytes(bytes.b)
    C::ContentReader.allocate.__send__(:initialize_reader, nil, stream, "probe", nil)
  end

  def content_reader_over_raw(bytes)
    C::ContentReader.__send__(:create, nil, CNA::Runtime::Stream.over_bytes(bytes.b), "probe", nil)
  end
end
