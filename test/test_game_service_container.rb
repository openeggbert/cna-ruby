# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"
require_relative "../tools/api_compat/verifier"

# Foundation 33 — `GameServiceContainer`, and the two BCL identities it needed.
#
# Four identities over one private `Dictionary<Type, object>`, reaching no native entry point and
# holding no unmanaged resource. It was blocked on `System.Type` and `System.IServiceProvider`, and
# the two need opposite treatments:
#
# - `System.Type` is a **type token**, and Ruby has one: a `Module`. It gets a register entry.
# - `System.IServiceProvider` declares one member the implementing type already declares publicly.
#   Ruby has no interfaces, so it gets a recorded decision **not** to invent a constant.
class GameServiceContainerTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path

  F = Microsoft::Xna::Framework
  B = CNA::Runtime::BclProjection

  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)
  IL = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read)
  RULES = JSON.parse(ROOT.join("tools", "api_compat", "mapping-rules.json").read)
  REFERENCE = JSON.parse(ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read)

  module ServiceContract; end
  class Provider
    include ServiceContract
  end
  class Unrelated; end

  def container = F::GameServiceContainer.new

  # ------------------------------------------------------------------------------- the contract

  def test_it_is_complete_and_pure_managed
    name = "Microsoft.Xna.Framework.GameServiceContainer"
    assert_includes STRICT.fetch("completeTypeNames"), name
    assert_equal 0, STRICT.fetch("localDiagnostics").fetch(name)
    entry = IL.fetch("types").fetch(name)
    refute entry.fetch("nativeReachable")
    assert_empty entry.fetch("nativeReachableMethods")
    assert_equal "Microsoft.Xna.Framework.Game.dll", entry.fetch("assembly")
    # One private field: the Dictionary<Type, object> every member reads.
    assert_equal 1, entry.fetch("declaredFields")
    assert_equal ["public"], entry.fetch("constructors").map { |ctor| ctor.fetch("access") }
  end

  def test_the_public_surface_is_exactly_the_four_declared_identities
    assert_equal %i[AddService GetService RemoveService],
                 F::GameServiceContainer.public_instance_methods(false).sort
    declared = REFERENCE.fetch("types").find { |type| type.fetch("name").end_with?("GameServiceContainer") }
    assert_equal [%w[constructor .ctor], %w[method AddService], %w[method GetService],
                  %w[method RemoveService]],
                 declared.fetch("members").map { |member| [member.fetch("kind"), member.fetch("name")] }.sort
    # Publicly constructible, unlike most of the Game family.
    assert_instance_of F::GameServiceContainer, container
  end

  # ------------------------------------------------------------------------ System.Type projection

  def test_system_type_projects_to_a_ruby_module
    assert_equal "Module", B::TYPES.fetch("System.Type")
    assert_equal Module, Object.const_get(B::TYPES.fetch("System.Type"), false)
    assert_includes B.identities, "System.Type"
    assert_includes RULES.fetch("bclProjection").fetch("types"), "System.Type"
    # A Class is a Module, so both work as a service key.
    assert_kind_of Module, Provider
    assert_kind_of Module, ServiceContract
  end

  def test_system_i_service_provider_collapses_to_the_member_it_declares
    assert_includes B::STRUCTURAL_COLLAPSE.keys, "System.IServiceProvider"
    assert B.structural_collapse?("System.IServiceProvider")
    assert_includes B::STRUCTURAL_COLLAPSE.fetch("System.IServiceProvider"), "GetService"
    # No constant was invented for it, anywhere.
    refute Object.const_defined?(:IServiceProvider, false)
    refute CNA::Runtime.const_defined?(:IServiceProvider, false)
    refute Object.const_defined?(:System, false)
    # And its whole declared surface is present as a member of the implementing type.
    assert F::GameServiceContainer.public_method_defined?(:GetService)
  end

  # The register records a decision not to invent a constant, so the verifier has to catch one being
  # invented later. Without this the entry would be a comment.
  def test_mutation_inventing_a_constant_for_a_collapsed_identity_is_caught
    CNA::Runtime.const_set(:IServiceProvider, Module.new)
    result = CNAApiCompat::Verifier.new(reference: {"types" => []}, target: {"types" => []}, runtime: true).verify
    assert_operator result.counts.fetch("LANGUAGE_MAPPING_MISMATCH"), :>, 0
  ensure
    CNA::Runtime.__send__(:remove_const, :IServiceProvider)
  end

  def test_the_shipped_register_is_accepted
    result = CNAApiCompat::Verifier.new(reference: {"types" => []}, target: {"types" => []}, runtime: true).verify
    assert_equal 0, result.counts.fetch("LANGUAGE_MAPPING_MISMATCH")
  end

  # ---------------------------------------------------------------------------------- AddService

  def test_add_service_stores_the_provider_under_its_key
    services = container
    provider = Provider.new
    assert_nil services.AddService(Provider, provider)
    assert_same provider, services.GetService(Provider)
    # An interface key works too: IsAssignableFrom is `provider.is_a?(type)`.
    assert_nil services.AddService(ServiceContract, provider)
    assert_same provider, services.GetService(ServiceContract)
  end

  # The IL opens with two null checks naming their parameters, then a duplicate-key check naming
  # "type", then the assignability check, which names no parameter at all.
  def test_add_service_validates_exactly_what_the_il_validates
    services = container
    provider = Provider.new

    null_type = assert_raises(ArgumentError) { services.AddService(nil, provider) }
    assert_equal "type", null_type.message
    null_provider = assert_raises(ArgumentError) { services.AddService(Provider, nil) }
    assert_equal "provider", null_provider.message

    services.AddService(Provider, provider)
    duplicate = assert_raises(ArgumentError) { services.AddService(Provider, provider) }
    assert_equal "type", duplicate.message

    unassignable = assert_raises(ArgumentError) { services.AddService(Unrelated, provider) }
    assert_equal "ArgumentError", unassignable.message,
                 "the CLR names no parameter here and its message is a localized resource"

    # The type token itself must be a Ruby type token.
    assert_raises(TypeError) { services.AddService("Provider", provider) }
    assert_raises(TypeError) { services.AddService(42, provider) }
  end

  def test_a_refused_add_stores_nothing
    services = container
    provider = Provider.new
    assert_raises(ArgumentError) { services.AddService(Unrelated, provider) }
    assert_nil services.GetService(Unrelated)
    assert_raises(ArgumentError) { services.AddService(Provider, nil) }
    assert_nil services.GetService(Provider)
  end

  # The dictionary's default comparer is reference equality on the Type, and a Ruby Module key in a
  # Hash compares the same way: two distinct anonymous modules never collide.
  def test_keys_compare_by_identity
    services = container
    first = Module.new
    second = Module.new
    left = Object.new
    left.extend(first)
    right = Object.new
    right.extend(second)
    services.AddService(first, left)
    services.AddService(second, right)
    assert_same left, services.GetService(first)
    assert_same right, services.GetService(second)
  end

  # ---------------------------------------------------------------------- RemoveService, GetService

  # `Dictionary.Remove`'s result is popped, so removing a key that was never added is harmless.
  def test_remove_service_is_harmless_when_the_key_is_absent
    services = container
    provider = Provider.new
    services.AddService(Provider, provider)
    assert_nil services.RemoveService(Provider)
    assert_nil services.GetService(Provider)
    assert_nil services.RemoveService(Provider)
    assert_nil services.RemoveService(Unrelated)
    # And the key can be added again afterwards.
    assert_nil services.AddService(Provider, provider)
    assert_same provider, services.GetService(Provider)
  end

  def test_remove_service_validates_its_type
    error = assert_raises(ArgumentError) { container.RemoveService(nil) }
    assert_equal "type", error.message
    assert_raises(TypeError) { container.RemoveService("Provider") }
  end

  # `ContainsKey` then the indexer, else `ldnull` — an absent service answers nil rather than
  # raising, which is the one place this type differs from the dictionary it wraps.
  def test_get_service_answers_nil_for_an_absent_key_rather_than_raising
    services = container
    assert_nil services.GetService(Provider)
    assert_nil services.GetService(ServiceContract)
    services.AddService(Provider, Provider.new)
    assert_nil services.GetService(Unrelated)
  end

  def test_get_service_validates_its_type
    error = assert_raises(ArgumentError) { container.GetService(nil) }
    assert_equal "type", error.message
    assert_raises(TypeError) { container.GetService(42) }
  end

  def test_containers_are_independent
    first = container
    second = container
    provider = Provider.new
    first.AddService(Provider, provider)
    assert_nil second.GetService(Provider)
    assert_same provider, first.GetService(Provider)
  end

  # -------------------------------------------------------------------- nothing populates one

  def test_nothing_in_this_binding_registers_a_service
    assert_nil container.GetService(F::IGraphicsDeviceManager)
    # Game.Services is the producer, and Game is one of the six deferred partial runtime types.
    refute F::Game.public_method_defined?(:Services)
    assert_includes STRICT.fetch("partialTypes").keys, "Microsoft.Xna.Framework.Game"
    source = ROOT.join("lib", "microsoft", "xna", "framework", "game.rb").read
    refute_includes source, "GameServiceContainer.new"
  end
end
