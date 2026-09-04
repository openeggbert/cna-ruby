# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `StorageDevice`, `StorageContainer`, and the async façade that turns out not to be one.
#
# `BeginShowSelector`'s whole IL validates, constructs a `StorageDeviceAsyncResult` whose
# `ManualResetEvent` is created **already signalled** and whose `CompletedSynchronously` is
# `ldc.i4.1`, invokes the callback **inline** and returns it. CNA says the same of its side — "no
# operation handle is invented for work that never pends" — so one C route carries each Begin/End
# pair, and the projection is the shape both of them actually have.
class StorageTest < Minitest::Test
  F = Microsoft::Xna::Framework
  S = Microsoft::Xna::Framework::Storage
  R = CNA::Runtime
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze

  def native? = !ENV["CNA_NATIVE_LIBRARY"].to_s.empty?

  def skip_unless_native
    skip "CNA_NATIVE_LIBRARY not supplied" unless native?
  end

  # A device, and a uniquely named container that is deleted afterwards however the test ends.
  def with_container(name = "CnaRubyTest#{Process.pid}")
    device = S::StorageDevice.EndShowSelector(S::StorageDevice.BeginShowSelector(nil, nil))
    container = device.EndOpenContainer(device.BeginOpenContainer(name, nil, nil))
    yield device, container
  ensure
    container&.Dispose
    device&.DeleteContainer(name)
  end

  # ------------------------------------------------------------------ the surface

  def test_both_types_are_complete
    %w[StorageDevice StorageContainer].each do |name|
      assert ReviewedScoreboard.complete?(STRICT, "Microsoft.Xna.Framework.Storage.#{name}"), name
    end
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
  end

  # Neither has a public constructor: XNA's are `assembly`, and the only way to a device is the
  # selector.
  def test_neither_can_be_constructed
    [S::StorageDevice, S::StorageContainer].each do |klass|
      refute klass.singleton_class.public_method_defined?(:new), klass.to_s
      assert_raises(NoMethodError) { klass.new }
    end
  end

  # `DeviceChanged` is a **static** event in XNA — one field on the type — so it is one here, and
  # the verifier measures it on the singleton rather than as a missing instance event.
  def test_device_changed_is_a_static_event
    assert S::StorageDevice.singleton_class.public_method_defined?(:DeviceChanged)
    refute S::StorageDevice.public_method_defined?(:DeviceChanged)
    assert_instance_of R::Event, S::StorageDevice.DeviceChanged
    %i[add_DeviceChanged remove_DeviceChanged DeviceChanged=].each do |leaked|
      refute S::StorageDevice.singleton_class.method_defined?(leaked), leaked.to_s
    end
  end

  # The stream a container's files open as is not an XNA identity and does not live in the XNA
  # namespace: it is the `System.IO.Stream` projection with a native backing.
  def test_the_storage_stream_is_a_runtime_type_not_an_xna_one
    refute S.const_defined?(:StorageStream, false)
    assert_operator R::StorageStream, :<, R::Stream
    assert_equal 0, STRICT.fetch("INTERNAL_TYPE_LEAK")
  end

  # ------------------------------------------------------------------ the BCL decisions

  def test_the_register_carries_the_five_identities_the_family_needed
    types = R::BclProjection::TYPES
    assert_equal "CNA::Runtime::AsyncResult", types.fetch("System.IAsyncResult")
    assert_equal "CNA::Runtime::AsyncResult::WaitHandle", types.fetch("System.Threading.WaitHandle")
    assert_equal "CNA::Runtime::Stream::FileMode", types.fetch("System.IO.FileMode")
    assert_equal "CNA::Runtime::Stream::FileAccess", types.fetch("System.IO.FileAccess")
    assert_equal "CNA::Runtime::Stream::FileShare", types.fetch("System.IO.FileShare")
    # `AsyncCallback` is collapsed rather than given a constant, the way `Action`1` is.
    assert R::BclProjection.structural_collapse?("System.AsyncCallback")
    refute R.const_defined?(:AsyncCallback, false)
  end

  # Every value read out of the pinned mscorlib. `FileMode` has **no zero**, and the other two are
  # `[Flags]`.
  def test_the_three_io_enums_are_the_pinned_values
    def values(enum)
      enum.constants.reject { |name| name == :CLR_IDENTITY }
          .to_h { |name| [name.to_s, enum.const_get(name).to_i] }
    end
    assert_equal({ "CreateNew" => 1, "Create" => 2, "Open" => 3, "OpenOrCreate" => 4,
                   "Truncate" => 5, "Append" => 6 }.sort, values(R::Stream::FileMode).sort)
    assert_equal({ "Read" => 1, "Write" => 2, "ReadWrite" => 3 }.sort,
                 values(R::Stream::FileAccess).sort)
    assert_equal({ "None" => 0, "Read" => 1, "Write" => 2, "ReadWrite" => 3, "Delete" => 4,
                   "Inheritable" => 16 }.sort, values(R::Stream::FileShare).sort)
    # `FileMode` has no zero at all, which is what makes a default-constructed one invalid in the
    # CLR too, and the other two are `[Flags]`.
    refute_includes values(R::Stream::FileMode).values, 0
    # And CNA's own identities, read out of the header by the ABI gate, are numerically the same.
    constants = CNA::Native::Manifest::CONSTANTS
    assert_equal 3, constants.fetch("CNA_FILE_MODE_OPEN")
    assert_equal 3, constants.fetch("CNA_FILE_ACCESS_READ_WRITE")
    assert_equal 16, constants.fetch("CNA_FILE_SHARE_INHERITABLE")
  end

  # ------------------------------------------------------------------ the async that is not

  # `BeginShowSelector` completes before it returns: the callback has already run, the result says
  # so, and its wait handle is signalled.
  def test_begin_show_selector_completes_synchronously_and_calls_back_inline
    skip_unless_native

    seen = []
    result = S::StorageDevice.BeginShowSelector(->(r) { seen << r }, :my_state)
    assert_equal 1, seen.length, "the callback runs inside Begin"
    assert_same result, seen.first
    assert_equal :my_state, result.AsyncState
    assert_equal true, result.CompletedSynchronously
    assert_equal true, result.IsCompleted
    assert_equal true, result.AsyncWaitHandle.WaitOne
    assert_equal true, result.AsyncWaitHandle.WaitOne(0)
    device = S::StorageDevice.EndShowSelector(result)
    assert_instance_of S::StorageDevice, device
  end

  # `if (endHasBeenCalled) throw new InvalidOperationException(CannotEndTwice)`.
  def test_end_refuses_a_second_call_and_a_foreign_result
    skip_unless_native

    result = S::StorageDevice.BeginShowSelector(nil, nil)
    S::StorageDevice.EndShowSelector(result)
    error = assert_raises(RuntimeError) { S::StorageDevice.EndShowSelector(result) }
    assert_equal "Cannot call End twice.", error.message
    assert_raises(ArgumentError) { S::StorageDevice.EndShowSelector(nil) }
    assert_raises(ArgumentError) { S::StorageDevice.EndShowSelector(Object.new) }
  end

  # The four overloads, told apart by arity, with the IL's two guards.
  def test_the_four_selector_overloads_and_their_guards
    skip_unless_native

    device = S::StorageDevice.EndShowSelector(S::StorageDevice.BeginShowSelector(nil, nil))
    assert_instance_of S::StorageDevice, device
    device = S::StorageDevice.EndShowSelector(
      S::StorageDevice.BeginShowSelector(F::PlayerIndex::One, nil, nil)
    )
    assert_instance_of S::StorageDevice, device
    device = S::StorageDevice.EndShowSelector(S::StorageDevice.BeginShowSelector(1024, 2, nil, nil))
    assert_instance_of S::StorageDevice, device
    device = S::StorageDevice.EndShowSelector(
      S::StorageDevice.BeginShowSelector(F::PlayerIndex::Two, 1024, 2, nil, nil)
    )
    assert_instance_of S::StorageDevice, device
    # `sizeInBytes < 0` is `ArgumentOutOfRangeException("sizeInBytes")`.
    assert_raises(RangeError) { S::StorageDevice.BeginShowSelector(-1, 0, nil, nil) }
    assert_raises(ArgumentError) { S::StorageDevice.BeginShowSelector(nil) }
  end

  # `EndOpenContainer` checks `ReferenceEquals(this, result.storageDevice)` and refuses a result
  # from another device with `ArgumentException(IAsyncNotFromBegin, "result")`.
  #
  # And the IL sets `endHasBeenCalled = true` **before** that check — `IL_0028` precedes `IL_002f`
  # — so a refused call still consumes the result and the right device cannot use it afterwards.
  # Surprising, faithful, and asserted rather than tidied up.
  def test_open_container_refuses_a_result_from_another_device_and_consumes_it_anyway
    skip_unless_native

    name = "CnaRubyForeign#{Process.pid}"
    first = S::StorageDevice.EndShowSelector(S::StorageDevice.BeginShowSelector(nil, nil))
    second = S::StorageDevice.EndShowSelector(S::StorageDevice.BeginShowSelector(nil, nil))
    result = first.BeginOpenContainer(name, nil, nil)
    assert_raises(ArgumentError) { second.EndOpenContainer(result) }
    error = assert_raises(RuntimeError) { first.EndOpenContainer(result) }
    assert_equal "Cannot call End twice.", error.message
    # The container the refused Begin already opened is real; a fresh Begin reaches it.
    container = first.EndOpenContainer(first.BeginOpenContainer(name, nil, nil))
    container.Dispose
    first.DeleteContainer(name)
  end

  # ------------------------------------------------------------------ the device

  def test_the_three_device_properties_are_the_file_systems
    skip_unless_native

    device = S::StorageDevice.EndShowSelector(S::StorageDevice.BeginShowSelector(nil, nil))
    assert_equal true, device.IsConnected
    assert_kind_of Integer, device.FreeSpace
    assert_kind_of Integer, device.TotalSpace
    assert_operator device.TotalSpace, :>, 0
    assert_operator device.FreeSpace, :>=, 0
    assert_operator device.FreeSpace, :<=, device.TotalSpace
  end

  # `if (titleName == null) throw new ArgumentNullException(..., TitleNameNotNull)`, and a name
  # that names nothing is not an error.
  def test_delete_container_refuses_null_and_tolerates_a_name_that_names_nothing
    skip_unless_native

    device = S::StorageDevice.EndShowSelector(S::StorageDevice.BeginShowSelector(nil, nil))
    assert_raises(ArgumentError) { device.DeleteContainer(nil) }
    assert_nil device.DeleteContainer("CnaRubyNoSuchContainer#{Process.pid}")
  end

  # ------------------------------------------------------------------ the container

  def test_a_container_reports_its_name_and_its_device
    skip_unless_native

    with_container("CnaRubyNamed#{Process.pid}") do |device, container|
      assert_equal "CnaRubyNamed#{Process.pid}", container.DisplayName
      assert_same device, container.StorageDevice
      refute container.IsDisposed
    end
  end

  # Directories and files, created, tested, enumerated and removed.
  def test_the_file_system_members_do_what_they_say
    skip_unless_native

    with_container do |_device, container|
      refute container.DirectoryExists("levels")
      container.CreateDirectory("levels")
      assert container.DirectoryExists("levels")

      refute container.FileExists("save.dat")
      stream = container.CreateFile("save.dat")
      stream.Write("hello", 0, 5)
      assert_equal 5, stream.Length
      assert_equal 5, stream.Position
      stream.Close
      assert container.FileExists("save.dat")

      assert_equal ["save.dat"], container.GetFileNames
      assert_equal ["levels"], container.GetDirectoryNames
      assert_equal ["save.dat"], container.GetFileNames("*.dat")
      assert_empty container.GetFileNames("*.png")

      container.DeleteFile("save.dat")
      container.DeleteDirectory("levels")
      assert_empty container.GetFileNames
      assert_empty container.GetDirectoryNames
    end
  end

  # A file written and read back through the native stream, incrementally rather than as one blob.
  def test_a_file_round_trips_through_the_stream
    skip_unless_native

    with_container do |_device, container|
      stream = container.CreateFile("bytes.bin")
      assert_equal true, stream.CanWrite
      assert_equal true, stream.CanSeek
      stream.Write("abcdefgh", 0, 8)
      stream.Flush
      stream.Close

      reader = container.OpenFile("bytes.bin", R::Stream::FileMode::Open)
      assert_equal 8, reader.Length
      buffer = "\0" * 4
      assert_equal 4, reader.Read(buffer, 0, 4)
      assert_equal "abcd", buffer
      assert_equal 4, reader.Position
      assert_equal 6, reader.Seek(6, R::Stream::SeekOrigin::Begin)
      tail = "\0" * 2
      assert_equal 2, reader.Read(tail, 0, 2)
      assert_equal "gh", tail
      reader.Close
      container.DeleteFile("bytes.bin")
    end
  end

  # The three `OpenFile` overloads, told apart by arity.
  def test_the_three_open_file_overloads
    skip_unless_native

    with_container do |_device, container|
      container.CreateFile("modes.bin").Close
      [[R::Stream::FileMode::Open],
       [R::Stream::FileMode::Open, R::Stream::FileAccess::Read],
       [R::Stream::FileMode::Open, R::Stream::FileAccess::Read, R::Stream::FileShare::Read]]
        .each do |arguments|
        stream = container.OpenFile("modes.bin", *arguments)
        assert_instance_of R::StorageStream, stream
        stream.Close
      end
      container.DeleteFile("modes.bin")
    end
  end

  # `ValidateArguments` refuses a null **and an empty** path by name, which is the IL's
  # `String.IsNullOrEmpty` rather than a null check.
  def test_every_path_member_refuses_a_null_or_empty_path
    skip_unless_native

    with_container do |_device, container|
      [->(v) { container.DirectoryExists(v) }, ->(v) { container.FileExists(v) },
       ->(v) { container.CreateDirectory(v) }, ->(v) { container.DeleteDirectory(v) },
       ->(v) { container.CreateFile(v) }, ->(v) { container.DeleteFile(v) },
       ->(v) { container.OpenFile(v, R::Stream::FileMode::Open) }].each do |call|
        assert_raises(ArgumentError) { call.call(nil) }
        assert_raises(ArgumentError) { call.call("") }
      end
    end
  end

  # `Dispose()` raises `Disposing` before it releases anything, and a second call does nothing.
  def test_dispose_raises_disposing_once_and_is_idempotent
    skip_unless_native

    device = S::StorageDevice.EndShowSelector(S::StorageDevice.BeginShowSelector(nil, nil))
    name = "CnaRubyDispose#{Process.pid}"
    container = device.EndOpenContainer(device.BeginOpenContainer(name, nil, nil))
    seen = []
    container.Disposing.add(->(sender, args) { seen << [sender.equal?(container), args] })
    container.Dispose
    assert_equal [[true, CNA::Runtime::EventArgs::Empty]], seen
    assert container.IsDisposed
    container.Dispose
    assert_equal 1, seen.length, "a second Dispose does nothing"
    device.DeleteContainer(name)
  end

  # `Dispose(false)` returns at its first instruction, and `Finalize` is that — a bare `ret`.
  def test_dispose_false_and_finalize_do_nothing
    skip_unless_native

    with_container("CnaRubyFinalize#{Process.pid}") do |_device, container|
      seen = []
      container.Disposing.add(->(_s, _a) { seen << :disposing })
      container.Dispose(false)
      assert_empty seen
      refute container.IsDisposed
      assert_nil container.__send__(:Finalize)
      refute container.IsDisposed
    end
  end

  # Every member refuses on a disposed container — `VerifyNotDisposed` is `ValidateArguments`'s
  # first statement, before the null check.
  def test_a_disposed_container_refuses_everything
    skip_unless_native

    device = S::StorageDevice.EndShowSelector(S::StorageDevice.BeginShowSelector(nil, nil))
    name = "CnaRubyDisposed#{Process.pid}"
    container = device.EndOpenContainer(device.BeginOpenContainer(name, nil, nil))
    container.Dispose
    assert_raises(CNA::DisposedObjectError) { container.FileExists("a") }
    assert_raises(CNA::DisposedObjectError) { container.CreateDirectory("a") }
    assert_raises(CNA::DisposedObjectError) { container.GetFileNames }
    # The disposed check comes **first**: a null path on a disposed container is still a disposal
    # failure, not an argument one.
    assert_raises(CNA::DisposedObjectError) { container.FileExists(nil) }
    device.DeleteContainer(name)
  end
end
