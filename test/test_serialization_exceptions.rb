# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# Foundation 49 — the `System.Runtime.Serialization` carrier, and the two XNA exception types it
# unblocks.
#
# `Content.ContentLoadException` and `Storage.StorageDeviceNotConnectedException` were deferred
# through eight milestones as "a BCL cluster no otherwise-unblocked type needs". What that cluster
# really costs is two nominal identities — and what makes them *nominal* rather than markers is a
# Ruby fact, not a preference: both types declare **two two-argument constructors**, and Ruby has no
# overload by parameter type.
class SerializationExceptionsTest < Minitest::Test
  F = Microsoft::Xna::Framework
  B = CNA::Runtime::BclProjection
  INFO = CNA::Runtime::SerializationInfo
  CONTEXT = CNA::Runtime::StreamingContext
  ROOT = Pathname(__dir__).join("..").expand_path

  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  RULES = JSON.parse(ROOT.join("tools", "api_compat", "mapping-rules.json").read).freeze

  TYPES = {
    "Microsoft.Xna.Framework.Content.ContentLoadException" => F::Content::ContentLoadException,
    "Microsoft.Xna.Framework.Storage.StorageDeviceNotConnectedException" =>
      F::Storage::StorageDeviceNotConnectedException
  }.freeze

  # ------------------------------------------------------------------------- the pinned contract

  # Four constructors each, and the fourth is the `family` serialization form. The two bases differ:
  # ContentLoadException extends System.Exception directly, the storage one extends
  # ExternalException, which the register collapses to the nearest projected ancestor.
  def test_both_declare_the_four_constructor_exception_shape
    { "Microsoft.Xna.Framework.Content.ContentLoadException" => "System.Exception",
      "Microsoft.Xna.Framework.Storage.StorageDeviceNotConnectedException" =>
        "System.Runtime.InteropServices.ExternalException" }.each do |name, base|
      type = REFERENCE.fetch(name)
      assert_equal base, type.fetch("baseType"), name
      members = type.fetch("members")
      assert_equal 4, members.length, name
      assert(members.all? { |member| member.fetch("kind") == "constructor" }, name)
      shapes = members.map do |member|
        [member.fetch("access"), member.fetch("parameters").map { |parameter| parameter.fetch("type") }]
      end
      assert_equal [["public", []],
                    ["public", %w[System.String]],
                    ["public", %w[System.String System.Exception]],
                    ["protected", %w[System.Runtime.Serialization.SerializationInfo
                                     System.Runtime.Serialization.StreamingContext]]],
                   shapes, name
    end
  end

  # The fact that decides the whole projection: two of the four take two arguments.
  def test_two_of_the_four_constructors_take_two_arguments
    TYPES.each_key do |name|
      two = REFERENCE.fetch(name).fetch("members")
                     .count { |member| member.fetch("parameters").length == 2 }
      assert_equal 2, two, name
    end
  end

  def test_both_types_are_complete
    TYPES.each_key do |name|
      refute_includes STRICT.fetch("missingTypeNames"), name
      assert_includes STRICT.fetch("completeTypeNames"), name
    end
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_equal ReviewedScoreboard::MISSING_TYPES, STRICT.fetch("MISSING_TYPES")
  end

  # Storage was a new namespace holding exactly one type, the shape Audio and Media took in
  # Foundation 16. The two runtime types joined it when Storage was built; what this milestone
  # claimed, and still claims, is that **it** added only the exception. `StorageDeviceAsyncResult`
  # is `private` in XNA and is not a projected identity here either -- what a consumer holds is the
  # `IAsyncResult` projection, which lives in `CNA::Runtime` because it is a BCL type.
  def test_the_storage_namespace_holds_only_selected_types
    assert_equal %i[StorageContainer StorageDevice StorageDeviceNotConnectedException],
                 F::Storage.constants.sort
    %i[StorageDeviceAsyncResult StorageContainerOpenAsyncResult StorageStream].each do |absent|
      refute F::Storage.const_defined?(absent, false), absent
    end
  end

  # ------------------------------------------------------------------------------- the register

  def test_both_carrier_identities_are_registered_and_the_rules_agree
    %w[System.Runtime.Serialization.SerializationInfo
       System.Runtime.Serialization.StreamingContext].each do |identity|
      assert_includes B.identities, identity
      assert_instance_of Class, Object.const_get(B::TYPES.fetch(identity), false)
    end
    assert_equal ReviewedScoreboard::BCL_PROJECTED_IDENTITIES, STRICT.fetch("BCL_PROJECTED_IDENTITIES")
    assert_equal B::TYPES.transform_keys(&:to_s), RULES.fetch("bclProjection").fetch("types")
  end

  # StreamingContextStates is the type of StreamingContext.State, but the selected reference never
  # names it, and the register admits only identities that surface really names.
  def test_the_states_enum_is_a_support_type_and_not_a_registered_identity
    refute_includes B.identities, "System.Runtime.Serialization.StreamingContextStates"
    assert_instance_of Class, CNA::Runtime::StreamingContextStates
    refute Object.const_defined?(:System)
  end

  def test_serialization_exception_is_a_measured_thrown_exception
    assert_equal "CNA::Runtime::SerializationError",
                 B::THROWN_EXCEPTIONS.fetch("System.Runtime.Serialization.SerializationException")
    assert_equal 8, STRICT.fetch("BCL_THROWN_EXCEPTIONS")
    assert_operator CNA::Runtime::SerializationError, :<, ::StandardError
    refute_operator CNA::Runtime::SerializationError, :<, ::ScriptError
    refute_includes B.identities, "System.Runtime.Serialization.SerializationException"
    assert_includes RULES.fetch("bclProjection").fetch("thrownExceptions")
                         .fetch("System.Runtime.Serialization.SerializationException"),
                    "CNA::Runtime::SerializationError"
  end

  # ------------------------------------------------------------------------- SerializationInfo

  # `AddValue(name, value, type)` throws ArgumentNullException("name") on a null name and
  # SerializationException(Serialization_SameNameTwice) on a duplicate; `GetElement` throws
  # SerializationException(Serialization_NotFound) when FindElement answers -1.
  def test_the_carrier_carries_the_exact_validations
    info = INFO.new
    assert_equal 0, info.MemberCount
    assert_nil info.AddValue("Message", "hello")
    assert_equal 1, info.MemberCount
    assert_equal "hello", info.GetValue("Message")
    assert_raises(CNA::Runtime::SerializationError) { info.AddValue("Message", "again") }
    assert_raises(CNA::Runtime::SerializationError) { info.GetValue("absent") }
    assert_raises(ArgumentError) { info.AddValue(nil, 1) }
    assert_raises(ArgumentError) { info.GetValue(nil) }
    # A stored nil is a value, not an absence.
    info.AddValue("Nothing", nil)
    assert_nil info.GetValue("Nothing")
    assert_equal 2, info.MemberCount
  end

  # It carries what the XNA surface can reach and no more: mscorlib's forty typed overloads are
  # conveniences over the general pair, and the type-resolution protocol belongs to a formatter.
  def test_the_carrier_surface_is_the_narrow_one
    assert_equal %i[AddValue GetValue MemberCount].sort, INFO.public_instance_methods(false).sort
    %i[SetType FullTypeName AssemblyName ObjectType GetEnumerator GetInt32 GetString].each do |absent|
      refute INFO.public_method_defined?(absent), absent
    end
  end

  # ------------------------------------------------------------------------- StreamingContext

  # A `sequential sealed` value type over two fields, with value equality and a hash of the state.
  def test_the_context_is_a_value_with_the_pinned_defaults
    context = CONTEXT.new
    assert_equal CNA::Runtime::StreamingContextStates::All, context.State
    assert_nil context.Context
    assert context.frozen?
    assert_equal CONTEXT.new, context
    assert_equal CONTEXT.new.hash, context.hash

    other = CONTEXT.new(CNA::Runtime::StreamingContextStates::File, "payload")
    assert_equal CNA::Runtime::StreamingContextStates::File, other.State
    assert_equal "payload", other.Context
    refute_equal context, other
  end

  # The pinned flags enum: eight named bits and All = 0xFF, with no named zero.
  def test_the_states_enum_is_the_pinned_flags_enum
    states = CNA::Runtime::StreamingContextStates
    { "CrossProcess" => 1, "CrossMachine" => 2, "File" => 4, "Persistence" => 8,
      "Remoting" => 16, "Other" => 32, "Clone" => 64, "CrossAppDomain" => 128,
      "All" => 255 }.each do |name, value|
      assert_equal value, states.const_get(name).to_i, name
    end
    refute states.constants.map(&:to_s).any? { |name| states.const_get(name).to_i.zero? }
  end

  # ------------------------------------------------------------------------- the constructors

  def test_the_three_public_constructors_forward_as_the_other_six_exception_types_do
    TYPES.each_value do |klass|
      assert_operator klass, :<, StandardError
      assert_equal klass.name, klass.new.message
      assert_equal "boom", klass.new("boom").message
      inner = RuntimeError.new("inner")
      raised = klass.new("boom", inner)
      assert_equal "boom", raised.message
      assert_same inner, raised.cause
      assert_nil raised.backtrace
    end
  end

  # The dispatch the nominal carrier makes possible: a `SerializationInfo` first argument selects
  # the serialization form, anything else the message form.
  def test_the_two_two_argument_constructors_are_told_apart_by_the_carrier
    info = INFO.new
    info.AddValue("Message", "from the carrier")
    context = CONTEXT.new
    TYPES.each_value do |klass|
      from_carrier = klass.new(info, context)
      assert_equal "from the carrier", from_carrier.message
      assert_nil from_carrier.cause

      inner = RuntimeError.new("inner")
      from_message = klass.new("direct", inner)
      assert_equal "direct", from_message.message
      assert_same inner, from_message.cause
    end
  end

  # `System.Exception`'s serialization constructor reads eleven named values; Ruby's exception base
  # holds one of them. An absent Message is an absence, not an error, and the other ten are not
  # fabricated.
  def test_an_empty_carrier_yields_an_exception_with_no_message
    TYPES.each_value do |klass|
      raised = klass.new(INFO.new, CONTEXT.new)
      assert_equal klass.name, raised.message
    end
  end

  def test_the_other_ten_serialized_values_are_not_invented
    info = INFO.new
    %w[ClassName Message Data HelpURL StackTraceString RemoteStackTraceString
       RemoteStackIndex ExceptionMethod HResult Source].each_with_index do |name, index|
      info.AddValue(name, "value-#{index}")
    end
    TYPES.each_value do |klass|
      raised = klass.new(info, CONTEXT.new)
      assert_equal "value-1", raised.message, "only Message crosses"
      %i[ClassName HelpURL StackTraceString HResult Source].each do |absent|
        refute_respond_to raised, absent
      end
    end
  end

  # ------------------------------------------------------------------------------- no runtime

  def test_neither_type_implies_a_runtime_and_nothing_raises_them
    # ContentManager exists now and *does* raise ContentLoadException -- for an unsupported `T`, a
    # cache hit of the wrong type and a load CNA refuses, which is what XNA raises it for. What this
    # milestone claimed, and still claims, is that **it** built none of that: it projected two
    # serialization carriers and completed two exception types, and neither is raised by anything it
    # added. So the claim narrows to the one type no member of this binding raises, and the
    # ContentManager case is asserted where it belongs, in `test_content_manager.rb`.
    refute F::Content.const_defined?(:ContentReader, false)
    sources = Dir[ROOT.join("lib", "**", "*.rb")].flat_map do |path|
      File.readlines(path).reject { |line| line.strip.start_with?("#") }
    end
    refute(sources.any? { |line| line.include?("raise") && line.include?("StorageDeviceNotConnectedException") })
    raisers = sources.select { |line| line.include?("raise") && line.include?("ContentLoadException") }
    refute_empty raisers, "ContentManager raises it; if that stops being true this test is stale"
  end
end
