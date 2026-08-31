# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"
require_relative "../tools/api_compat/verifier"

# Foundation 30 — `System.NotSupportedException` projects to `CNA::Runtime::NotSupportedError`.
#
# The obvious Ruby candidate is wrong, and being wrong here is silent rather than loud:
# `NotImplementedError` reads like the right name and descends from `ScriptError`, not
# `StandardError`, so a bare `rescue` does not catch it. A CLR `catch (Exception)` is exactly a bare
# `rescue`, so mapping to it would let a routine, recoverable CLR failure escape a caller's error
# handling entirely — the same trap this binding already documents for abstract-contract members.
#
# So the mapping is a real dedicated class under StandardError, and the register that records it is
# a **third** register, separate from TYPES and EXCEPTION_BASES, because a thrown exception is never
# named by an XNA public signature and must never be counted as a mapped BCL identity.
class NotSupportedErrorTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path

  B = CNA::Runtime::BclProjection
  E = CNA::Runtime::NotSupportedError

  RULES = JSON.parse(ROOT.join("tools", "api_compat", "mapping-rules.json").read)
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)
  BCL = JSON.parse(ROOT.join("docs", "generated", "bcl-inventory.json").read)

  # ------------------------------------------------------------------------------- the mapping

  def test_the_clr_identity_maps_to_the_dedicated_ruby_class
    assert_equal "CNA::Runtime::NotSupportedError", B::THROWN_EXCEPTIONS.fetch("System.NotSupportedException")
    assert_equal "CNA::Runtime::NotSupportedError", B.thrown_exception("System.NotSupportedException")
    assert_equal E, Object.const_get(B::THROWN_EXCEPTIONS.fetch("System.NotSupportedException"), false)
    assert_equal "CNA::Runtime::NotSupportedError", E.name
    assert_instance_of Class, E
  end

  def test_the_existing_thrown_exception_mappings_are_undisturbed
    assert_equal({"System.ArgumentNullException" => "ArgumentError",
                  "System.ArgumentOutOfRangeException" => "RangeError",
                  "System.ArgumentException" => "ArgumentError",
                  "System.IndexOutOfRangeException" => "IndexError",
                  "System.NotSupportedException" => "CNA::Runtime::NotSupportedError",
                  # Added by Foundation 32; see test_touch_panel.rb.
                  "System.InvalidOperationException" => "RuntimeError",
                  # Added by Foundation 46; see test_dictionary.rb.
                  "System.Collections.Generic.KeyNotFoundException" => "KeyError",
                  # Added by Foundation 49; see test_serialization_exceptions.rb.
                  "System.Runtime.Serialization.SerializationException" =>
                    "CNA::Runtime::SerializationError"},
                 B::THROWN_EXCEPTIONS)
    assert_equal 8, STRICT.fetch("BCL_THROWN_EXCEPTIONS")
    assert_equal B::THROWN_EXCEPTIONS, STRICT.fetch("bclProjection").fetch("thrownExceptions")
  end

  # The runtime register and the committed rules must agree, rather than each stating the mapping
  # separately and being free to drift.
  def test_the_rules_file_and_the_runtime_register_name_the_same_identities
    documented = RULES.fetch("bclProjection").fetch("thrownExceptions")
                      .keys.reject { |key| key == "policy" || !key.start_with?("System.") }
    assert_equal B::THROWN_EXCEPTIONS.keys.sort, documented.sort
    assert_includes RULES.fetch("bclProjection").fetch("thrownExceptions")
                         .fetch("System.NotSupportedException"), "CNA::Runtime::NotSupportedError"
  end

  # A thrown exception is not an identity the XNA public surface names, so it must stay out of the
  # register the dependency frontier consumes as "mapped BCL types".
  def test_thrown_exceptions_are_a_separate_register_from_the_named_identities
    B::THROWN_EXCEPTIONS.each_key { |identity| refute_includes B.identities, identity }
    assert_equal B::THROWN_EXCEPTIONS.keys.sort, B.thrown_identities
    assert_equal 13, STRICT.fetch("BCL_PROJECTED_IDENTITIES"), "unchanged by the thrown-exception register"

    frontier = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read)
    B::THROWN_EXCEPTIONS.each_key { |identity| refute_includes frontier.fetch("mappedBclTypes"), identity }
  end

  # ---------------------------------------------------------------------------- the hierarchy

  def test_it_is_a_standard_error_an_ordinary_rescue_catches
    assert_operator E, :<, StandardError
    assert_operator E, :<, ::Exception

    caught = begin
      raise E, "refused"
    rescue => error
      error
    end
    assert_instance_of E, caught
    assert_equal "refused", caught.message

    # And by its own name, which is the point of giving it one.
    named = begin
      raise E
    rescue CNA::Runtime::NotSupportedError => error
      error.class
    end
    assert_equal E, named
  end

  def test_it_is_not_a_script_error_and_not_ruby_s_not_implemented_error
    refute_operator E, :<=, ::ScriptError
    refute_equal ::NotImplementedError, E
    refute_operator E, :<=, ::NotImplementedError
    refute_operator ::NotImplementedError, :<=, E

    # The trap, stated as a fact about Ruby rather than an opinion: a bare rescue misses it.
    assert_operator ::NotImplementedError, :<, ::ScriptError
    refute_operator ::NotImplementedError, :<=, ::StandardError
    escaped = begin
      begin
        raise ::NotImplementedError
      rescue StandardError
        :caught
      end
    rescue ::NotImplementedError
      :escaped
    end
    assert_equal :escaped, escaped
  end

  def test_it_is_not_an_alias_of_an_existing_ruby_exception
    [::RuntimeError, ::ArgumentError, ::TypeError, ::IndexError, ::RangeError,
     ::FrozenError].each do |other|
      refute_equal other, E, other.name
      refute_operator E, :<=, other, other.name
    end
    refute_equal ::StandardError, E, "the root itself would lose the identity"
    # It is the only exception class in the CNA runtime namespace, and it is a BCL projection.
    exceptions = CNA::Runtime.constants(false).select do |name|
      value = CNA::Runtime.const_get(name, false)
      value.instance_of?(Class) && value <= ::Exception
    end
    assert_equal %i[NotSupportedError SerializationError], exceptions
  end

  # ---------------------------------------------------------- the measured mscorlib behaviour

  def test_the_hierarchy_matches_the_admitted_mscorlib
    types = BCL.fetch("types")
    assert_equal "System.SystemException", types.fetch("System.NotSupportedException").fetch("baseType")
    assert_equal "System.Exception", types.fetch("System.SystemException").fetch("baseType")
    # System.Exception is the identity the register already roots at StandardError, so the CLR
    # chain and the Ruby chain end in the same place.
    assert_equal "StandardError", B::EXCEPTION_BASES.fetch("System.Exception")
    assert_operator E, :<, StandardError
  end

  def test_the_three_public_constructor_shapes_are_the_measured_ones
    constructors = BCL.fetch("types").fetch("System.NotSupportedException").fetch("members")
                      .select { |entry| entry.fetch("kind") == "constructor" && entry.fetch("access") == "public" }
    assert_equal [[], ["string"], ["string", "class System.Exception"]],
                 constructors.map { |entry| entry.fetch("parameters").map { |parameter| parameter.fetch("type") } }

    assert_instance_of E, E.new
    assert_equal "message", E.new("message").message
    inner = ArgumentError.new("inner")
    with_inner = E.new("message", inner)
    assert_equal "message", with_inner.message
    assert_same inner, with_inner.cause, "the CLR stores innerException; Ruby's slot for it is cause"
    assert_nil with_inner.backtrace, "constructed but not raised, as the CLR has StackTrace null"
  end

  # The CLR default message is the localized framework resource Arg_NotSupportedException. It is
  # Microsoft's string, it is culture-dependent, and no XNA member exposes it observably, so it is
  # not reproduced.
  def test_the_parameterless_form_does_not_fabricate_the_clr_resource_message
    assert_equal "CNA::Runtime::NotSupportedError", E.new.message
    refute_includes E.new.message, "Specified method"
    refute_includes E.new.message, "not supported"
    # The CLR resource *name* is recorded as evidence; its English text is never reproduced. No
    # source or generated file in this repository carries the framework message.
    sources = (ROOT.join("lib").glob("**/*.rb") + ROOT.join("docs").glob("**/*")).select(&:file?)
    carrying = sources.select { |file| file.read.include?("Specified method is not supported") }
    assert_equal [], carrying.map { |file| file.relative_path_from(ROOT).to_s }
  end

  # --------------------------------------------------------------------- verifier mutations

  class ScriptErrorFixture < ::ScriptError; end
  class PlainObjectFixture; end
  class CorrectFixture < StandardError; end

  def diagnostics(replacement)
    original = B.const_get(:THROWN_EXCEPTIONS, false)
    B.__send__(:remove_const, :THROWN_EXCEPTIONS)
    B.const_set(:THROWN_EXCEPTIONS, original.merge(replacement).freeze)
    CNAApiCompat::Verifier.new(reference: {"types" => []}, target: {"types" => []}, runtime: true)
                          .verify.counts.fetch("LANGUAGE_MAPPING_MISMATCH")
  ensure
    B.__send__(:remove_const, :THROWN_EXCEPTIONS)
    B.const_set(:THROWN_EXCEPTIONS, original)
  end

  def test_the_shipped_register_is_accepted
    assert_equal 0, diagnostics({})
    assert_equal 0, diagnostics({"System.NotSupportedException" => "NotSupportedErrorTest::CorrectFixture"})
  end

  def test_mutation_not_implemented_error_substitution
    assert_operator diagnostics({"System.NotSupportedException" => "NotImplementedError"}), :>, 0
  end

  def test_mutation_any_script_error_subclass
    assert_operator diagnostics({"System.NotSupportedException" => "NotSupportedErrorTest::ScriptErrorFixture"}), :>, 0
    assert_operator diagnostics({"System.NotSupportedException" => "ScriptError"}), :>, 0
  end

  def test_mutation_an_ordinary_object_with_the_identity_lost
    assert_operator diagnostics({"System.NotSupportedException" => "NotSupportedErrorTest::PlainObjectFixture"}), :>, 0
    assert_operator diagnostics({"System.NotSupportedException" => "Object"}), :>, 0
  end

  def test_mutation_an_unresolved_constant_or_a_wrong_namespace
    assert_operator diagnostics({"System.NotSupportedException" => "CNA::Runtime::Nope"}), :>, 0
    assert_operator diagnostics({"System.NotSupportedException" => "System::NotSupportedException"}), :>, 0
    refute Object.const_defined?(:System, false)
  end

  # A generic StandardError is catchable but loses the identity. The register cannot reject that on
  # shape alone, so the rule is stated where it can be checked: the mapping must be a class of its
  # own, never the bare root.
  def test_a_generic_standard_error_would_lose_the_identity
    refute_equal ::StandardError, E
    assert_operator E, :<, ::StandardError
    B::THROWN_EXCEPTIONS.each_value do |path|
      resolved = path.split("::").reduce(Object) { |scope, part| scope.const_get(part, false) }
      refute_equal ::StandardError, resolved, path
    end
  end
end
