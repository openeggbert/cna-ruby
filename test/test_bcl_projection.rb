# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"
require_relative "../tools/api_compat/verifier"

# Foundation 21 — the general BCL projection register and the XNA exception base mapping.
#
# The register records every non-XNA CLR identity this binding projects. It is measured, not
# aspirational: the API verifier resolves every entry and shape-checks every exception base, and the
# dependency frontier consumes the same register, so a BCL type can never be reported as mapped
# unless the runtime really projects it.
#
# The exception rule: a CLR type whose declared base is a projected exception base takes a Ruby
# exception superclass rather than Object. StandardError is the root, because a CLR
# `catch (Exception)` is the analogue of a bare Ruby `rescue`. Foundation 22 consumed six of the
# eight XNA exception types once the pinned XNA 4.0 Windows IL became available; the two whose
# selected surface includes a protected serialization constructor stay deferred.
class BclProjectionTest < Minitest::Test
  B = CNA::Runtime::BclProjection

  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read)
  BCL_INVENTORY = JSON.parse(ROOT.join("docs", "generated", "bcl-inventory.json").read)
  SIGNATURES = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)
  BY_NAME = REFERENCE.fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze

  EXCEPTIONS = %w[
    Microsoft.Xna.Framework.Audio.InstancePlayLimitException
    Microsoft.Xna.Framework.Audio.NoAudioHardwareException
    Microsoft.Xna.Framework.Audio.NoMicrophoneConnectedException
    Microsoft.Xna.Framework.Content.ContentLoadException
    Microsoft.Xna.Framework.Graphics.DeviceLostException
    Microsoft.Xna.Framework.Graphics.DeviceNotResetException
    Microsoft.Xna.Framework.Graphics.NoSuitableGraphicsDeviceException
    Microsoft.Xna.Framework.Storage.StorageDeviceNotConnectedException
  ].freeze

  # ------------------------------------------------------------------------------- the register

  def test_the_register_is_narrow_and_every_entry_resolves
    # Foundation 29 added ReadOnlyCollection`1, the first entry with a real member surface, which
    # is why Foundation 28 had to admit a BCL authority to measure it against.
    assert_equal({"System.EventArgs" => "CNA::Runtime::EventArgs",
                  "System.Collections.Generic.Dictionary`2" => "CNA::Runtime::Dictionary",
                  "System.Runtime.Serialization.SerializationInfo" => "CNA::Runtime::SerializationInfo",
                  "System.Runtime.Serialization.StreamingContext" => "CNA::Runtime::StreamingContext", "System.TimeSpan" => "Float",
                  "System.Attribute" => "CNA::Runtime::Attribute",
                  "System.Collections.ObjectModel.ReadOnlyCollection`1" => "CNA::Runtime::ReadOnlyCollection",
                  # Foundation 34 added the mutable sibling, measured against the same mscorlib.
                  "System.Collections.ObjectModel.Collection`1" => "CNA::Runtime::Collection",
                  "System.Collections.Generic.IList`1" => "Array",
                  "System.Char" => "Integer",
                  "System.Nullable`1" => "NilClass",
                  "System.Text.StringBuilder" => "String",
                  # Foundation 33: a type token, and Ruby's is a Module.
                  "System.Type" => "Module",
                  # The Stream projection, and the one identity that reaches this register
                  # transitively: no XNA signature names SeekOrigin, System.IO.Stream::Seek does.
                  "System.Byte[]" => "String",
                  "System.IO.Stream" => "CNA::Runtime::Stream",
                  # The ContentReader family's one register decision: the CLR base of
                  # Content.ContentReader, named by the reference contract exactly once and
                  # exactly there.
                  "System.IO.BinaryReader" => "CNA::Runtime::BinaryReader",
                  "System.IO.SeekOrigin" => "CNA::Runtime::Stream::SeekOrigin",
                  # The Storage family, and the second and third transitive demands: no XNA
                  # signature names WaitHandle -- IAsyncResult.AsyncWaitHandle does -- while the
                  # three IO enums are named directly by StorageContainer.OpenFile's overloads.
                  "System.IO.FileMode" => "CNA::Runtime::Stream::FileMode",
                  "System.IO.FileAccess" => "CNA::Runtime::Stream::FileAccess",
                  "System.IO.FileShare" => "CNA::Runtime::Stream::FileShare",
                  "System.IAsyncResult" => "CNA::Runtime::AsyncResult",
                  "System.Threading.WaitHandle" => "CNA::Runtime::AsyncResult::WaitHandle",
                  # Foundation 105: the demand-driven System.ComponentModel closure the thirteen
                  # Design converters reach, plus the reflection and globalization identities they
                  # reach through it. Seven ComponentModel identities and four scalar element
                  # converters come from the second admitted authority, System.dll; the four
                  # System.Reflection and two System.Globalization ones come from mscorlib.
                  # IDictionary collapses to Ruby's Hash because every CreateInstance does exactly
                  # get_Item on it, and ICollection to Array because that is what an
                  # InstanceDescriptor's Arguments is.
                  "System.ComponentModel.TypeConverter" => "CNA::Runtime::ComponentModel::TypeConverter",
                  "System.ComponentModel.ExpandableObjectConverter" => "CNA::Runtime::ComponentModel::ExpandableObjectConverter",
                  "System.ComponentModel.PropertyDescriptor" => "CNA::Runtime::ComponentModel::PropertyDescriptor",
                  "System.ComponentModel.PropertyDescriptorCollection" => "CNA::Runtime::ComponentModel::PropertyDescriptorCollection",
                  "System.ComponentModel.TypeDescriptor" => "CNA::Runtime::ComponentModel::TypeDescriptor",
                  "System.ComponentModel.Design.Serialization.InstanceDescriptor" => "CNA::Runtime::ComponentModel::InstanceDescriptor",
                  "System.ComponentModel.ITypeDescriptorContext" => "CNA::Runtime::ComponentModel::ITypeDescriptorContext",
                  "System.ComponentModel.BaseNumberConverter" => "CNA::Runtime::ComponentModel::BaseNumberConverter",
                  "System.ComponentModel.Int32Converter" => "CNA::Runtime::ComponentModel::Int32Converter",
                  "System.ComponentModel.SingleConverter" => "CNA::Runtime::ComponentModel::SingleConverter",
                  "System.ComponentModel.ByteConverter" => "CNA::Runtime::ComponentModel::ByteConverter",
                  "System.Globalization.CultureInfo" => "CNA::Runtime::Globalization::CultureInfo",
                  "System.Globalization.TextInfo" => "CNA::Runtime::Globalization::TextInfo",
                  "System.Reflection.MemberInfo" => "CNA::Runtime::Reflection::MemberInfo",
                  "System.Reflection.ConstructorInfo" => "CNA::Runtime::Reflection::ConstructorInfo",
                  "System.Reflection.FieldInfo" => "CNA::Runtime::Reflection::FieldInfo",
                  "System.Reflection.PropertyInfo" => "CNA::Runtime::Reflection::PropertyInfo",
                  "System.Collections.IDictionary" => "Hash",
                  "System.Collections.ICollection" => "Array"},
                 B::TYPES)
    # Foundation 33 also records a decision *not* to invent a constant, and Foundation 36 adds
    # the second such decision.
    # Foundation 105 adds the two interfaces a consumer must *construct* to use a projected member.
    # Both collapse to a Ruby callable for the same measured reason the first two do, and both were
    # measured in the BCL inventory before being collapsed rather than assumed to declare one member.
    assert_equal ["System.Action`1", "System.AsyncCallback", "System.Collections.IComparer",
                  "System.EventHandler", "System.IDisposable",
                  "System.IServiceProvider", "System.Resources.ResourceManager"],
                 B::STRUCTURAL_COLLAPSE.keys.sort
    # `IComparer` is an interface and really declares one member. `EventHandler` is a **delegate**
    # -- `extends System.MulticastDelegate` -- so the CLR generates `BeginInvoke`/`EndInvoke` beside
    # `Invoke` and a constructor taking an object and a native int. The contract is `Invoke` alone,
    # which is the same reading `System.Action`1` and `System.AsyncCallback` already take, and the
    # measurement is what says so rather than an assumption about how a delegate is shaped.
    comparer = BCL_INVENTORY.fetch("types").fetch("System.Collections.IComparer")
    assert_equal "interface", comparer.fetch("kind")
    assert_equal %w[Compare], comparer.fetch("members").map { |member| member.fetch("name") }

    handler = BCL_INVENTORY.fetch("types").fetch("System.EventHandler")
    assert_equal "System.MulticastDelegate", handler.fetch("baseType")
    assert_equal %w[.ctor BeginInvoke EndInvoke Invoke],
                 handler.fetch("members").map { |member| member.fetch("name") }.sort
    invoke = handler.fetch("members").find { |member| member.fetch("name") == "Invoke" }
    assert_equal ["object", "class System.EventArgs"], invoke.fetch("parameters").map { |p| p.fetch("type") }
    assert_equal({"System.Exception" => "StandardError",
                  "System.Runtime.InteropServices.ExternalException" => "StandardError"},
                 B::EXCEPTION_BASES)
    assert_equal [
       "System.Action`1", "System.AsyncCallback",
       "System.Attribute", "System.Byte[]",
       "System.Char", "System.Collections.Generic.Dictionary`2",
       "System.Collections.Generic.IList`1", "System.Collections.ICollection",
       "System.Collections.IComparer", "System.Collections.IDictionary",
       "System.Collections.ObjectModel.Collection`1", "System.Collections.ObjectModel.ReadOnlyCollection`1",
       "System.ComponentModel.BaseNumberConverter", "System.ComponentModel.ByteConverter",
       "System.ComponentModel.Design.Serialization.InstanceDescriptor", "System.ComponentModel.ExpandableObjectConverter",
       "System.ComponentModel.ITypeDescriptorContext", "System.ComponentModel.Int32Converter",
       "System.ComponentModel.PropertyDescriptor", "System.ComponentModel.PropertyDescriptorCollection",
       "System.ComponentModel.SingleConverter", "System.ComponentModel.TypeConverter",
       "System.ComponentModel.TypeDescriptor", "System.EventArgs",
       "System.EventHandler", "System.Exception",
       "System.Globalization.CultureInfo", "System.Globalization.TextInfo",
       "System.IAsyncResult", "System.IDisposable",
       "System.IO.BinaryReader", "System.IO.FileAccess",
       "System.IO.FileMode", "System.IO.FileShare",
       "System.IO.SeekOrigin", "System.IO.Stream",
       "System.IServiceProvider", "System.Nullable`1",
       "System.Reflection.ConstructorInfo", "System.Reflection.FieldInfo",
       "System.Reflection.MemberInfo", "System.Reflection.PropertyInfo",
       "System.Resources.ResourceManager", "System.Runtime.InteropServices.ExternalException",
       "System.Runtime.Serialization.SerializationInfo", "System.Runtime.Serialization.StreamingContext",
       "System.Text.StringBuilder", "System.Threading.WaitHandle",
       "System.TimeSpan", "System.Type"
    ], B.identities

    # Every projected identity resolves, and to a Ruby type rather than a value. Two of them
    # resolve to a bare Module rather than a Class, and both are Foundation 105's:
    #
    # - `TypeDescriptor` is a CLR **static class** -- `sealed` with no public constructor and no
    #   instance member. A Ruby class with a private `new` would carry an instance identity the CLR
    #   type does not have.
    # - `ITypeDescriptorContext` is an interface **this binding never implements**: the consumer
    #   supplies the context. A module is what a consumer includes, and it is the first interface
    #   this register has projected at all.
    #
    # `IAsyncResult` is the interface that shows why "interface implies module" would be the wrong
    # rule: XNA's own implementations of it are private and always completed, so what this binding
    # hands back is a concrete `AsyncResult`, and a consumer receives an instance.
    modules = B::TYPES.merge(B::EXCEPTION_BASES).filter_map do |identity, path|
      resolved = path.split("::").reduce(Object) { |scope, part| scope.const_get(part, false) }
      assert_kind_of Module, resolved, path
      identity unless resolved.instance_of?(Class)
    end
    assert_equal %w[System.ComponentModel.ITypeDescriptorContext System.ComponentModel.TypeDescriptor],
                 modules.sort
    # And the two that are modules really are the CLR shapes that justify it.
    assert_equal "interface",
                 BCL_INVENTORY.dig("types", "System.ComponentModel.ITypeDescriptorContext", "kind")
    static_class = BCL_INVENTORY.fetch("types").fetch("System.ComponentModel.TypeDescriptor")
    assert static_class.fetch("sealed")
    assert static_class.fetch("members").none? { |member| member.fetch("kind") == "constructor" && member.fetch("access") == "public" }

    # Deliberately not designed yet. Dictionary`2 was on this list until Foundation 46 measured it
    # against the same mscorlib, and the SerializationInfo/StreamingContext pair until Foundation 49
    # -- which the pinned reference does name, in the protected constructor two XNA exception types
    # declare. StreamingContextStates stays off because that surface never names it: it is a support
    # enum of the projection, not an identity the register admits.
    # System.IO.Stream was here until its own projection landed, and System.Text.StringBuilder until
    # SpriteFont's milestone measured it: a CLR StringBuilder is a mutable string and a Ruby String
    # is one, which is also what collapses SpriteFont's two MeasureString overloads exactly rather
    # than approximately.
    %w[System.Runtime.Serialization.StreamingContextStates
       System.Runtime.Serialization.SerializationException]
      .each { |absent| refute_includes B.identities, absent }
  end

  def test_every_register_identity_is_one_the_pinned_reference_actually_names
    signatures = REFERENCE.fetch("types").flat_map do |type|
      values = [type["baseType"], *type.fetch("directInterfaces", [])]
      type.fetch("members").each do |member|
        values.concat([member["type"], member["returnType"]])
        values.concat(member.fetch("parameters", []).map { |parameter| parameter["type"] })
      end
      values.compact
    end.uniq
    # One entry is admitted transitively rather than directly, and it is named here so the
    # exception is a decision rather than a hole: `System.IO.SeekOrigin` is named by
    # `System.IO.Stream::Seek` in the pinned mscorlib and by no XNA signature at all, yet a consumer
    # holding a stream this binding produced needs it to seek. `docs/generated/bcl-inventory.json`
    # carries the same rule and records which kind of demand each family has.
    # `WaitHandle` joined `SeekOrigin` as a transitive demand: no XNA signature names it, and
    # `IAsyncResult.AsyncWaitHandle` -- itself named by four Storage signatures -- does.
    #
    # The exceptions used to be a hand-kept list of two, which would have had to grow by ten at
    # Foundation 105 and could then have gone stale the way every hand-kept table in this project
    # eventually has. It reads the generated inventory instead: an identity no XNA signature names
    # must be a family the inventory records as `transitive` or `behavioural`, and the inventory's
    # own builder aborts on a family with neither kind of consumer. So the rule is measured on both
    # sides rather than restated here.
    families = BCL_INVENTORY.fetch("families").to_h { |entry| [entry.fetch("family"), entry] }
    indirect = []
    B.identities.each do |identity|
      next if signatures.any? { |signature| signature.include?(identity) }

      family = families[identity]
      refute_nil family, "#{identity} is in the register, no XNA signature names it, and it is not an admitted family"
      assert_includes %w[transitive behavioural], family.fetch("demand"), identity
      indirect << identity
    end
    # And the indirect ones stay the minority: most of the register is named outright.
    assert_operator indirect.length, :<, B.identities.length / 2
    # `SeekOrigin` remains the case that established the rule, and its one consumer is still the
    # member that reaches it.
    assert_equal ["System.IO.Stream::Seek"], families.fetch("System.IO.SeekOrigin").fetch("bclConsumers")
    assert_includes indirect, "System.IO.SeekOrigin"
    assert_includes indirect, "System.Threading.WaitHandle"
  end

  def test_the_strict_report_measures_the_register
    assert_equal ReviewedScoreboard::BCL_PROJECTED_IDENTITIES, STRICT.fetch("BCL_PROJECTED_IDENTITIES")
    assert_equal 2, STRICT.fetch("BCL_EXCEPTION_BASES")
    assert_equal({"types" => B::TYPES, "exceptionBases" => B::EXCEPTION_BASES,
                  "thrownExceptions" => B::THROWN_EXCEPTIONS},
                 STRICT.fetch("bclProjection"))
    assert_equal ReviewedScoreboard::BCL_THROWN_EXCEPTIONS, STRICT.fetch("BCL_THROWN_EXCEPTIONS")
    assert_equal 0, STRICT.fetch("LANGUAGE_MAPPING_MISMATCH")
    assert_equal 0, STRICT.fetch("BASE_MAPPING_MISMATCH")
  end

  def test_the_time_span_projection_is_measured_and_validating
    assert_equal "Float", B::TYPES.fetch("System.TimeSpan")
    assert_equal 1.25, B.time_span(1.25)
    assert_equal 2.0, B.time_span(2)
    assert_instance_of Float, B.time_span(2)
    error = assert_raises(TypeError) { B.time_span("1.25") }
    assert_equal "TimeSpan maps to numeric seconds", error.message
    assert_raises(TypeError) { B.time_span(nil) }
    # GameTime has projected TimeSpan this way since Foundation 1; the register now measures it.
    assert_equal 1.5, Microsoft::Xna::Framework::GameTime.new(1.5, 0.25).TotalGameTime
  end

  # ------------------------------------------------------------------- the exception base rule

  def test_standard_error_is_the_root_rather_than_ruby_exception
    B::EXCEPTION_BASES.each_value do |path|
      root = Object.const_get(path, false)
      assert_operator root, :<=, StandardError, path
      refute_equal ::Exception, root, "::Exception would put XNA failures beyond a bare rescue"
    end

    # A bare rescue must catch the projected root; ::Exception's own subclasses outside
    # StandardError deliberately would not be caught.
    caught = begin
      raise StandardError, "projected"
    rescue => error
      error.message
    end
    assert_equal "projected", caught
  end

  def test_only_the_two_bases_the_reference_names_are_projected
    declared = REFERENCE.fetch("types").filter_map { |type| type["baseType"] }
                        .select { |base| base.include?("Exception") }.uniq.sort
    assert_equal ["System.Exception", "System.Runtime.InteropServices.ExternalException"], declared
    assert_equal declared, B::EXCEPTION_BASES.keys.sort

    # ExternalException collapses to the nearest projected ancestor: the selected XNA surface never
    # names it, so no Ruby class is invented for it, and the two XNA types that derive from it take
    # StandardError directly.
    refute Object.const_defined?(:System, false)
    # No Ruby constant is invented for an XNA exception *base*. The one exception class the CNA
    # runtime carries is CNA::Runtime::NotSupportedError, added by Foundation 30, and it is a
    # projection of a CLR exception XNA members *throw*, never a base any XNA type derives from.
    # Sorted, because the claim is *which* classes exist and not what order Ruby's constant table
    # happens to list them in -- an ordering that shifts with load order and asserts nothing.
    assert_equal %i[NotSupportedError SerializationError], CNA::Runtime.constants(false).select { |name|
      value = CNA::Runtime.const_get(name, false)
      value.instance_of?(Class) && value <= ::Exception
    }.sort
    refute_includes B::EXCEPTION_BASES.values, "CNA::Runtime::NotSupportedError"
    refute_includes B::TYPES.values, "CNA::Runtime::NotSupportedError"
    [Microsoft::Xna::Framework::Audio::InstancePlayLimitException,
     Microsoft::Xna::Framework::Audio::NoAudioHardwareException].each do |klass|
      assert_equal StandardError, klass.superclass, klass.name
      assert_equal "System.Runtime.InteropServices.ExternalException",
                   BY_NAME.fetch("Microsoft.Xna.Framework.Audio.#{klass.name.split("::").last}").fetch("baseType")
    end
  end

  # ----------------------------------------------------------------------- verifier mutations

  def exception_contracts(ruby_name, base: "System.Exception")
    type = {
      "name" => "Microsoft.Xna.Framework.FixtureException", "rubyName" => ruby_name,
      "kind" => "class", "flags" => false, "baseType" => base, "interfaces" => [],
      "directInterfaces" => [], "genericParameters" => [], "members" => []
    }
    [{"types" => [Marshal.load(Marshal.dump(type))]}, {"types" => [Marshal.load(Marshal.dump(type))]}]
  end

  def base_mismatches(ruby_name, base: "System.Exception")
    reference, target = exception_contracts(ruby_name, base: base)
    CNAApiCompat::Verifier.new(reference: reference, target: target, runtime: true)
                          .verify.counts.fetch("BASE_MAPPING_MISMATCH")
  end

  # Stand-ins for a projected XNA exception, since no XNA exception type can be claimed yet.
  class CorrectFixture < StandardError; end
  class DeeperFixture < CorrectFixture; end
  class ObjectFixture; end
  class RubyExceptionFixture < ::Exception; end
  class UnrelatedFixture < Numeric; end

  def test_a_projected_exception_base_is_accepted
    assert_equal 0, base_mismatches("BclProjectionTest::CorrectFixture")
    assert_equal 0, base_mismatches("BclProjectionTest::CorrectFixture",
                                    base: "System.Runtime.InteropServices.ExternalException")
  end

  def test_mutation_exception_projected_as_an_ordinary_object_subclass
    assert_operator base_mismatches("BclProjectionTest::ObjectFixture"), :>, 0
  end

  def test_mutation_exception_projected_under_the_ruby_exception_root
    assert_operator base_mismatches("BclProjectionTest::RubyExceptionFixture"), :>, 0
  end

  def test_mutation_exception_projected_under_an_unrelated_class
    assert_operator base_mismatches("BclProjectionTest::UnrelatedFixture"), :>, 0
  end

  def test_mutation_exception_projected_too_deep_in_the_ruby_hierarchy
    # DeeperFixture is a StandardError, but not the class the register names.
    assert_operator base_mismatches("BclProjectionTest::DeeperFixture"), :>, 0
  end

  def test_mutation_a_non_exception_clr_base_must_not_take_an_exception_base
    assert_operator base_mismatches("BclProjectionTest::CorrectFixture", base: "System.Object"), :>, 0
  end

  def test_mutation_register_entry_that_does_not_resolve
    stubbed = {"System.EventArgs" => "CNA::Runtime::NotAThing"}
    with_register(CNA::Runtime::BclProjection, :TYPES, stubbed) do
      result = CNAApiCompat::Verifier.new(reference: {"types" => []}, target: {"types" => []}, runtime: true).verify
      assert_operator result.counts.fetch("LANGUAGE_MAPPING_MISMATCH"), :>, 0
    end
  end

  def test_mutation_exception_base_that_is_not_a_ruby_exception
    [{"System.Exception" => "Object"}, {"System.Exception" => "Comparable"},
     {"System.Exception" => "BclProjectionTest::RubyExceptionFixture"},
     {"System.Exception" => "CNA::Runtime::Nope"}].each do |stubbed|
      with_register(CNA::Runtime::BclProjection, :EXCEPTION_BASES, stubbed) do
        result = CNAApiCompat::Verifier.new(reference: {"types" => []}, target: {"types" => []}, runtime: true).verify
        assert_operator result.counts.fetch("LANGUAGE_MAPPING_MISMATCH"), :>, 0, stubbed.inspect
      end
    end
  end

  def with_register(owner, constant, replacement)
    original = owner.const_get(constant, false)
    owner.__send__(:remove_const, constant)
    owner.const_set(constant, replacement.freeze)
    yield
  ensure
    owner.__send__(:remove_const, constant)
    owner.const_set(constant, original)
  end

  # ------------------------------------------------------------- no exception type is claimed

  SERIALIZABLE = %w[
    Microsoft.Xna.Framework.Content.ContentLoadException
    Microsoft.Xna.Framework.Storage.StorageDeviceNotConnectedException
  ].freeze
  PROJECTED = (EXCEPTIONS - SERIALIZABLE).freeze

  def test_six_xna_exception_types_are_projected_and_two_stay_deferred
    assert_equal EXCEPTIONS.sort, BY_NAME.keys.grep(/Exception\z/).sort
    assert_equal 6, PROJECTED.length

    PROJECTED.each do |name|
      assert SIGNATURES.fetch("types").any? { |type| type.fetch("name") == name }, name
      assert_includes STRICT.fetch("completeTypeNames"), name
      assert_equal 0, STRICT.fetch("localDiagnostics").fetch(name), name
      runtime = name.split(".").reduce(Object) { |scope, part| scope.const_get(part, false) }
      assert_operator runtime, :<, StandardError, name
      assert_equal StandardError, runtime.superclass, name
    end

    # Foundation 49 projected the SerializationInfo/StreamingContext pair and completed both of
    # these, so what this milestone owns is no longer their absence but the split itself: they are
    # the two whose selected surface carries the protected serialization constructor, and the other
    # six declare only the public trio. `test_serialization_exceptions.rb` owns their behaviour.
    SERIALIZABLE.each do |name|
      assert SIGNATURES.fetch("types").any? { |type| type.fetch("name") == name }, name
      assert_includes STRICT.fetch("completeTypeNames"), name
      segments = name.split(".")
      scope = segments[0..-2].reduce(Object) { |context, part| context.const_get(part, false) }
      assert scope.const_defined?(segments.last.to_sym, false), name
    end
  end

  def test_every_xna_exception_declares_only_constructors
    EXCEPTIONS.each do |name|
      members = BY_NAME.fetch(name).fetch("members")
      assert(members.all? { |member| member.fetch("kind") == "constructor" }, name)
      refute_empty members, name
      members.each { |member| assert_nil member.fetch("returnType"), name }
    end

    # The two deferred types are exactly the two whose selected surface carries the protected
    # serialization constructor; the other six declare only the public trio.
    PROJECTED.each do |name|
      assert_equal 3, BY_NAME.fetch(name).fetch("members").length, name
      assert(BY_NAME.fetch(name).fetch("members").all? { |member| member.fetch("access") == "public" }, name)
    end
    SERIALIZABLE.each do |name|
      members = BY_NAME.fetch(name).fetch("members")
      assert_equal 4, members.length, name
      protected_ctor = members.find { |member| member.fetch("access") == "protected" }
      refute_nil protected_ctor, name
      assert_equal ["System.Runtime.Serialization.SerializationInfo",
                    "System.Runtime.Serialization.StreamingContext"],
                   protected_ctor.fetch("parameters").map { |parameter| parameter.fetch("type") }, name
      assert_includes B.identities, "System.Runtime.Serialization.SerializationInfo"
    end
  end
end
