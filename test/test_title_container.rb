# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require "tmpdir"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# The `System.IO.Stream` projection and `TitleContainer`, the first XNA member that produces one.
#
# Derivation, producer audit and the `System.Byte[]` decision: `docs/stream-projection-design.md`.
# Every assertion below states a defect it would catch, because a stream whose `Read` answers the
# requested count instead of the bytes really read, or whose `Position` does not advance, would pass
# any "no exception raised" test unchanged.
class TitleContainerTest < Minitest::Test
  F = Microsoft::Xna::Framework
  TC = F::TitleContainer
  S = CNA::Runtime::Stream
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read).freeze
  BCL = JSON.parse(ROOT.join("docs", "generated", "bcl-inventory.json").read).freeze

  ASSET = "hello title"
  NESTED = "\x00\x01\x02\xFF".b

  # ------------------------------------------------------------------- the contract, from metadata

  def test_it_is_the_static_class_the_reference_declares_with_exactly_one_member
    contract = REFERENCE.fetch("Microsoft.Xna.Framework.TitleContainer")
    assert_equal "class", contract.fetch("kind")
    assert contract.fetch("sealed")
    assert_equal 1, contract.fetch("members").length
    member = contract.fetch("members").first
    assert_equal %w[OpenStream System.IO.Stream], [member.fetch("name"), member.fetch("returnType")]
    assert member.fetch("static")
    assert_equal ["System.String"], member.fetch("parameters").map { |p| p.fetch("type") }

    # A static CLR class cannot be constructed, and Ruby carries that by making `new` private.
    assert_raises(NoMethodError) { TC.new }
    assert_equal %i[OpenStream], TC.singleton_methods(false).sort - %i[new]
  end

  def test_the_strict_scoreboard_records_it_complete
    assert_equal ReviewedScoreboard::TARGET_TYPES, STRICT.fetch("TARGET_TYPES")
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    refute_includes STRICT.fetch("missingTypes", []), "Microsoft.Xna.Framework.TitleContainer"
  end

  # The blocker it retired, and the one it did not.
  def test_the_stream_projection_consumed_title_container
    names = FRONTIER.fetch("dependencyCompleteCandidates").map { |item| item.fetch("name") }
    refute_includes names, "Microsoft.Xna.Framework.TitleContainer"
    # The consumable list was empty from Foundation 32 until IVertexType uncovered the four vertex
    # structs; what this test claims is that **this** projection made nothing consumable, and none
    # of the four is here.
    FRONTIER.fetch("consumableCandidates").each do |entry|
      assert_match(/VertexPosition/, entry.fetch("name"))
    end

    # ContentManager was the other half of what Stream unblocked, and the Action`1 decision that
    # followed consumed it too, so it is complete rather than waiting.
    assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.Content.ContentManager"
    FRONTIER.fetch("dependencyCompleteCandidates").each do |candidate|
      refute_includes candidate.fetch("unmappedBclTypes"), "System.IO.Stream", candidate.fetch("name")
    end
  end

  # ------------------------------------------------------------------------- the path algorithm

  # `GetCleanPath` and `IsCleanPathAbsolute`, transcribed from the IL. Each row would catch a
  # different transcription error, which is why they are a table rather than one happy path.
  def test_the_clean_path_algorithm_matches_the_il_case_by_case
    {
      "a/b.txt" => ["a\\b.txt", false],
      # `.\` is stripped repeatedly from the front.
      "./a/b.txt" => ["a\\b.txt", false],
      "././a" => ["a", false],
      # `\.\` collapses anywhere.
      "a/./b.txt" => ["a\\b.txt", false],
      # `\..\` collapses the segment before it.
      "a/x/../b.txt" => ["a\\b.txt", false],
      "a\\..\\b" => ["b", false],
      # A trailing `\.` is removed; a path that *is* `.` becomes empty.
      "x\\." => ["x", false],
      "." => ["", false],
      # A trailing `\..` collapses only when something precedes it.
      "x\\.." => ["", false],
      # The loop starts at index 1 and its IndexOf is the increment, so a *leading* `..\` is never
      # collapsed -- it survives to be rejected. That is the whole traversal defence.
      "../b.txt" => ["..\\b.txt", true],
      ".." => ["..", true],
      # A leading separator is absolute.
      "\\rooted" => ["\\rooted", true]
    }.each do |input, (clean, absolute)|
      assert_equal clean, TC.send(:clean_path, input), input
      assert_equal absolute, TC.send(:clean_path_absolute?, clean), input
    end
  end

  # The seven characters read out of the assembly's own static blob. Neither separator is among
  # them, which a "reject everything suspicious" reimplementation would get wrong.
  def test_the_bad_characters_are_exactly_the_seven_the_blob_carries
    assert_equal %w[: * ? " < > |], TC::BAD_CHARACTERS
    TC::BAD_CHARACTERS.each { |char| assert TC.send(:clean_path_absolute?, "a#{char}b"), char }
    ["\\", "/", ".", "-", "_", "~"].each do |char|
      refute TC.send(:clean_path_absolute?, "a#{char}b".tr("/", "\\")), char
    end
  end

  # ------------------------------------------------------------------------------ native reads

  def with_title_directory
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    Dir.mktmpdir("cna-title-") do |directory|
      File.binwrite(File.join(directory, "asset.txt"), ASSET)
      File.binwrite(File.join(directory, "empty.bin"), "")
      Dir.mkdir(File.join(directory, "sub"))
      File.binwrite(File.join(directory, "sub", "nested.bin"), NESTED)
      game = F::Game.new
      begin
        game.Tick
        host = game.instance_variable_get(:@host)
        view = CNA::Native::Layouts::StringView.new(directory.b)
        CNA::Native.library.call("cna_title_location_set_path_ext", host.handle,
                                 view.read_u64(0), view.read_u64(8))
        yield directory
      ensure
        game.Dispose
      end
    end
  end

  # The fixture is only meaningful if the override really took effect, so that is asserted rather
  # than assumed: the location CNA reports must be the directory the test made.
  def test_the_title_location_is_the_one_cna_reports
    with_title_directory do |directory|
      assert_equal directory, TC.send(:title_location)
    end
  end

  def test_open_stream_reads_a_title_file_through_cna
    with_title_directory do
      stream = TC.OpenStream("asset.txt")
      assert_instance_of S, stream
      assert_equal ASSET.bytesize, stream.Length
      assert_equal 0, stream.Position
      assert stream.CanRead
      assert stream.CanSeek
      refute stream.CanWrite, "a title asset is read-only"

      buffer = "\0".b * ASSET.bytesize
      assert_equal ASSET.bytesize, stream.Read(buffer, 0, ASSET.bytesize)
      assert_equal ASSET, buffer
      assert_equal ASSET.bytesize, stream.Position, "Read must advance Position by what it read"
      assert_equal 0, stream.Read(buffer, 0, ASSET.bytesize), "a second Read at the end answers zero"
    end
  end

  # Bytes, not text: a title asset is arbitrary binary and must survive unchanged.
  def test_a_nested_binary_asset_survives_byte_for_byte
    with_title_directory do
      stream = TC.OpenStream("sub/nested.bin")
      buffer = "\0".b * NESTED.bytesize
      assert_equal NESTED.bytesize, stream.Read(buffer, 0, NESTED.bytesize)
      assert_equal NESTED, buffer
      assert_equal Encoding::BINARY, buffer.encoding
    end
  end

  def test_a_name_is_normalized_before_it_reaches_the_reader
    with_title_directory do
      assert_equal ASSET.bytesize, TC.OpenStream("sub/../asset.txt").Length
      assert_equal ASSET.bytesize, TC.OpenStream("./asset.txt").Length
      assert_equal ASSET.bytesize, TC.OpenStream(".\\asset.txt").Length
    end
  end

  def test_an_empty_file_is_a_zero_length_stream_and_not_a_failure
    with_title_directory do
      stream = TC.OpenStream("empty.bin")
      assert_equal 0, stream.Length
      assert_equal(-1, stream.ReadByte)
    end
  end

  # XNA collapses FileNotFoundException, DirectoryNotFoundException and ArgumentException into one
  # FileNotFoundException; CNA collapses the same cases into CNA_RESULT_IO. Ruby's own identity for
  # "the file is not there" is Errno::ENOENT, and it descends from StandardError so a bare rescue
  # catches it as a CLR `catch (Exception)` would.
  def test_a_missing_file_and_a_missing_directory_are_the_same_refusal
    with_title_directory do
      %w[missing.txt sub/missing.bin nowhere/asset.txt].each do |name|
        error = assert_raises(Errno::ENOENT, name) { TC.OpenStream(name) }
        assert_includes error.message, TC.send(:title_location)
      end
    end
  end

  def test_every_refusal_the_il_declares
    with_title_directory do
      # String.IsNullOrEmpty -> ArgumentNullException("name")
      [nil, ""].each { |name| assert_raises(ArgumentError) { TC.OpenStream(name) } }
      # IsCleanPathAbsolute -> ArgumentException, and it is the traversal defence
      ["../escape", "..", "\\rooted", "a/../../escape", "bad:name", "a?b"].each do |name|
        assert_raises(ArgumentError, name) { TC.OpenStream(name) }
      end
    end
  end

  # Each opened stream is its own object over its own bytes: two opens must not share a position.
  def test_repeated_opens_are_independent
    with_title_directory do
      first = TC.OpenStream("asset.txt")
      second = TC.OpenStream("asset.txt")
      refute_same first, second
      first.Read("\0".b * 5, 0, 5)
      assert_equal 5, first.Position
      assert_equal 0, second.Position
      first.Close
      assert_equal 0, second.Position, "closing one must not disturb the other"
      assert_equal ASSET.bytesize, second.Length
    end
  end

  # -------------------------------------------------------------------- the projection itself

  def test_the_register_maps_the_clr_identity_and_the_measurement_backs_it
    register = CNA::Runtime::BclProjection::TYPES
    assert_equal "CNA::Runtime::Stream", register.fetch("System.IO.Stream")
    assert_equal "CNA::Runtime::Stream::SeekOrigin", register.fetch("System.IO.SeekOrigin")
    assert_equal "System.IO.Stream", S::CLR_IDENTITY

    measured = BCL.fetch("types").fetch("System.IO.Stream")
    assert measured.fetch("abstract"), "the CLR type is abstract, which is why `new` is private here"
    assert_raises(NoMethodError) { S.new }

    # Every projected member is one the measurement carries.
    names = measured.fetch("members").map { |item| item.fetch("name") }
    S::CLR_SURFACE.each do |identity|
      assert(names.include?(identity.to_s) || names.include?("get_#{identity}"), identity)
    end
    # And the reached surface stops where the derivation says it stops.
    %i[BeginRead EndRead BeginWrite EndWrite Synchronized Null CreateWaitHandle].each do |absent|
      refute_includes S::CLR_SURFACE, absent
      refute S.public_method_defined?(absent), absent
      refute S.respond_to?(absent), absent
    end
  end

  def test_seek_origin_is_the_enum_the_pinned_mscorlib_measures
    literals = BCL.fetch("types").fetch("System.IO.SeekOrigin").fetch("members")
                  .select { |item| item.key?("literal") }
                  .to_h { |item| [item.fetch("name"), Integer(item.fetch("literal")[/0x[0-9a-f]+/i], 16)] }
    assert_equal({ "Begin" => 0, "Current" => 1, "End" => 2 }, literals)
    literals.each do |name, value|
      assert_equal value, S::SeekOrigin.const_get(name).to_i, name
    end
    # It takes the binding's ordinary enum policy, so a bare Integer is not a SeekOrigin.
    assert S::SeekOrigin < CNA::Runtime::EnumValue
  end

  def test_seek_moves_from_each_origin_and_refuses_a_negative_target
    with_title_directory do
      stream = TC.OpenStream("asset.txt")
      assert_equal 3, stream.Seek(3, S::SeekOrigin::Begin)
      assert_equal 5, stream.Seek(2, S::SeekOrigin::Current)
      assert_equal ASSET.bytesize - 5, stream.Seek(-5, S::SeekOrigin::End)
      assert_equal ASSET.bytesize - 5, stream.Position, "Seek must answer the position it set"
      assert_raises(IndexError) { stream.Seek(-1, S::SeekOrigin::Begin) }
      assert_raises(ArgumentError) { stream.Seek(0, 0) }
    end
  end

  # `System.Byte[]` projects to a binary Ruby String, and the two properties a CLR array does not
  # have are refused rather than silently allowed.
  def test_read_refuses_a_frozen_or_undersized_buffer_and_never_resizes_one
    with_title_directory do
      stream = TC.OpenStream("asset.txt")
      assert_raises(ArgumentError) { stream.Read("ab".dup.freeze, 0, 1) }
      assert_raises(ArgumentError) { stream.Read("\0".b * 2, 0, 5) }
      assert_raises(RangeError) { stream.Read("\0".b * 8, -1, 1) }
      assert_raises(RangeError) { stream.Read("\0".b * 8, 0, -1) }
      assert_raises(TypeError) { stream.Read(nil, 0, 1) }

      buffer = "\0".b * 32
      stream.Read(buffer, 4, 5)
      assert_equal 32, buffer.bytesize, "Read must not resize the caller's buffer"
      assert_equal ASSET[0, 5], buffer[4, 5]
      assert_equal "\0".b * 4, buffer[0, 4], "Read must write only at the offset it was given"
    end
  end

  def test_a_read_only_stream_refuses_every_write_and_a_closed_one_refuses_everything
    with_title_directory do
      stream = TC.OpenStream("asset.txt")
      assert_raises(CNA::Runtime::NotSupportedError) { stream.Write("x".b, 0, 1) }
      assert_raises(CNA::Runtime::NotSupportedError) { stream.WriteByte(1) }
      assert_raises(CNA::Runtime::NotSupportedError) { stream.SetLength(0) }
      refute stream.CanTimeout
      assert_raises(RuntimeError) { stream.ReadTimeout }
      assert_raises(RuntimeError) { stream.WriteTimeout }

      stream.Close
      stream.Close # idempotent, like the CLR's
      stream.Dispose
      refute stream.CanRead
      assert_raises(CNA::DisposedObjectError) { stream.Length }
      assert_raises(CNA::DisposedObjectError) { stream.Read("\0".b, 0, 1) }
      assert_raises(CNA::DisposedObjectError) { stream.Seek(0, S::SeekOrigin::Begin) }
    end
  end

  # CopyTo starts where the stream is, not at the beginning -- a reimplementation that rewound
  # first would pass a test that only ever copied a fresh stream.
  def test_copy_to_copies_from_the_current_position_and_leaves_the_source_at_its_end
    with_title_directory do
      source = TC.OpenStream("asset.txt")
      source.Seek(6, S::SeekOrigin::Begin)
      destination = S.__send__(:over_bytes, +"", writable: true)
      source.CopyTo(destination, 4)
      assert_equal ASSET.bytesize, source.Position
      assert_equal ASSET.bytesize - 6, destination.Length

      destination.Position = 0
      buffer = "\0".b * destination.Length
      destination.Read(buffer, 0, buffer.bytesize)
      assert_equal ASSET[6..], buffer
    end
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_adds_no_content_pipeline_and_no_storage_runtime
    %i[ContentReader ContentTypeReader].each do |absent|
      refute F::Content.const_defined?(absent, false), absent.to_s
    end
    # The two Storage runtime types left this list when they were built; what this milestone
    # claimed, and still claims, is that **it** built neither -- `TitleContainer` reads the title's
    # own read-only content and reaches no storage container at all.
    %i[StorageDevice StorageContainer].each do |present|
      assert F::Storage.const_defined?(present, false), present.to_s
    end
    refute_includes CNA::Native::Manifest::FUNCTIONS.map(&:symbol), "cna_title_container_write_ext"
    refute F.const_defined?(:TitleLocation, false), "TitleLocation is assembly-internal in XNA"
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:constants), CNA::Native::Manifest::CONSTANTS.length
  end
end
