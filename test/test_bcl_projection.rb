# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
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
# `catch (Exception)` is the analogue of a bare Ruby `rescue`. No XNA exception type is claimed by
# this milestone — all eight declare constructors whose behaviour lives in XNA IL that this host
# does not carry.
class BclProjectionTest < Minitest::Test
  B = CNA::Runtime::BclProjection

  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read)
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
    assert_equal({"System.EventArgs" => "CNA::Runtime::EventArgs"}, B::TYPES)
    assert_equal({"System.Exception" => "StandardError",
                  "System.Runtime.InteropServices.ExternalException" => "StandardError"},
                 B::EXCEPTION_BASES)
    assert_equal ["System.EventArgs", "System.Exception",
                  "System.Runtime.InteropServices.ExternalException"], B.identities

    B::TYPES.merge(B::EXCEPTION_BASES).each_value do |path|
      resolved = path.split("::").reduce(Object) { |scope, part| scope.const_get(part, false) }
      assert_instance_of Class, resolved, path
    end

    # Deliberately not designed yet.
    %w[System.Type System.IServiceProvider System.IO.Stream System.TimeSpan System.Attribute
       System.Text.StringBuilder System.Runtime.Serialization.SerializationInfo
       System.Collections.ObjectModel.ReadOnlyCollection`1 System.Collections.Generic.Dictionary`2]
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
    B.identities.each do |identity|
      assert(signatures.any? { |signature| signature.include?(identity) }, identity)
    end
  end

  def test_the_strict_report_measures_the_register
    assert_equal 3, STRICT.fetch("BCL_PROJECTED_IDENTITIES")
    assert_equal 2, STRICT.fetch("BCL_EXCEPTION_BASES")
    assert_equal({"types" => B::TYPES, "exceptionBases" => B::EXCEPTION_BASES},
                 STRICT.fetch("bclProjection"))
    assert_equal 0, STRICT.fetch("LANGUAGE_MAPPING_MISMATCH")
    assert_equal 0, STRICT.fetch("BASE_MAPPING_MISMATCH")
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
    # names it, so no Ruby constant is invented for it.
    refute Object.const_defined?(:System, false)
    refute CNA::Runtime.const_defined?(:ExternalException, false)
    refute CNA::Runtime.const_defined?(:XnaException, false)
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

  def test_no_xna_exception_type_is_projected
    assert_equal EXCEPTIONS.sort, BY_NAME.keys.grep(/Exception\z/).sort
    EXCEPTIONS.each do |name|
      refute SIGNATURES.fetch("types").any? { |type| type.fetch("name") == name }, name
      assert_includes STRICT.fetch("missingTypeNames"), name
      # Neither the type nor, in the Content and Storage cases, the namespace that would hold it.
      segments = name.split(".")
      scope = segments[0..-2].reduce(Object) do |context, part|
        break nil unless context&.const_defined?(part, false)

        context.const_get(part, false)
      end
      refute scope&.const_defined?(segments.last.to_sym, false), name
    end
  end

  def test_every_xna_exception_declares_only_constructors_whose_il_is_absent
    EXCEPTIONS.each do |name|
      members = BY_NAME.fetch(name).fetch("members")
      assert(members.all? { |member| member.fetch("kind") == "constructor" }, name)
      refute_empty members, name

      # The pinned contract carries signatures only, so what a constructor does to Message and
      # InnerException — and what the parameterless one produces at all — is not on this host.
      members.each do |member|
        assert_equal %w[kind name static access returnType genericParameters parameters].sort,
                     member.keys.sort, name
        assert_nil member.fetch("returnType"), name
      end
    end
  end
end
