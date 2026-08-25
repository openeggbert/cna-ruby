# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/microsoft/xna/framework/input/touch"

# Foundation 17 — the Microsoft.Xna.Framework.Input.Touch managed closure.
#
# The two enums share the pure managed enum battery in test_pure_managed_enum_batch.rb. This file
# pins the TouchPanelCapabilities value contract and the exact namespace boundary: the closure is
# three managed value contracts and nothing that implies a touch device.
class TouchClosureTest < Minitest::Test
  F = Microsoft::Xna::Framework
  I = F::Input
  T = I::Touch
  CAPABILITIES = T::TouchPanelCapabilities

  REFERENCE = JSON.parse(
    Pathname(__dir__).join("..", "tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze

  SIGNATURES = JSON.parse(
    Pathname(__dir__).join("..", "tools", "api_compat", "signatures.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze

  CAPABILITIES_NAME = "Microsoft.Xna.Framework.Input.Touch.TouchPanelCapabilities"

  def test_capabilities_matches_the_pinned_struct_contract
    pinned = REFERENCE.fetch(CAPABILITIES_NAME)
    assert_equal "struct", pinned.fetch("kind")
    assert_equal "System.ValueType", pinned.fetch("baseType")
    assert_equal true, pinned.fetch("sealed")
    assert_empty pinned.fetch("directInterfaces")

    members = pinned.fetch("members")
    assert_equal 2, members.length
    assert(members.all? { |member| member.fetch("kind") == "property" })
    assert(members.none? { |member| member.fetch("static") })
    assert_equal({"IsConnected" => "System.Boolean", "MaximumTouchCount" => "System.Int32"},
                 members.to_h { |member| [member.fetch("name"), member.fetch("type")] })

    # Every property is get-only, so no setter identity may be projected.
    assert(members.all? { |member| member.fetch("get") })
    assert(members.none? { |member| member.fetch("set") })

    # XNA declares no public constructor; the CLR default struct value is the only reachable one.
    refute members.any? { |member| member.fetch("kind") == "constructor" }
    assert_equal members, SIGNATURES.fetch(CAPABILITIES_NAME).fetch("members")
  end

  def test_capabilities_projects_the_clr_default_struct_value
    capabilities = CAPABILITIES.new
    assert_instance_of CAPABILITIES, capabilities
    assert_equal false, capabilities.IsConnected
    assert_equal 0, capabilities.MaximumTouchCount
    assert_kind_of Integer, capabilities.MaximumTouchCount

    # Read-only: no setter exists for either property.
    %i[IsConnected= MaximumTouchCount=].each do |name|
      refute_respond_to capabilities, name
      refute CAPABILITIES.public_method_defined?(name), name.to_s
      refute CAPABILITIES.private_method_defined?(name), name.to_s
    end
    assert_raises(NoMethodError) { capabilities.IsConnected = true }
  end

  def test_capabilities_copies_are_independent_values
    original = CAPABILITIES.new
    copy = original.dup
    refute_same original, copy
    assert_equal original.IsConnected, copy.IsConnected
    assert_equal original.MaximumTouchCount, copy.MaximumTouchCount

    frozen = CAPABILITIES.new.freeze
    assert_predicate frozen.clone, :frozen?
    refute_predicate frozen.clone(freeze: false), :frozen?
    refute_predicate frozen.dup, :frozen?
  end

  def test_capabilities_exposes_exactly_the_two_declared_identities
    # dup/clone are language-only value-copy projections, not XNA identities; the verifier allows
    # exactly this set and the two declared property readers.
    assert_equal %i[IsConnected MaximumTouchCount clone dup],
                 CAPABILITIES.public_instance_methods(false).sort
    assert_equal %i[IsConnected MaximumTouchCount],
                 (CAPABILITIES.public_instance_methods(false) - %i[dup clone]).sort
    assert_empty CAPABILITIES.protected_instance_methods(false)
    assert_equal Object, CAPABILITIES.superclass
    # The defaults table is a private implementation constant, not a public identity.
    refute_includes CAPABILITIES.constants(false), :PROPERTIES
    assert_raises(NameError) { CAPABILITIES::PROPERTIES }

    # No invented device API of any kind.
    %i[GetCapabilities IsGestureAvailable ReadGesture GetState EnabledGestures
       DisplayWidth DisplayHeight DisplayOrientation HasPressure].each do |name|
      refute_respond_to CAPABILITIES, name
      refute CAPABILITIES.public_method_defined?(name), name.to_s
    end
  end

  def test_touch_namespace_holds_exactly_the_three_managed_contracts
    assert_equal %i[GestureType TouchLocationState TouchPanelCapabilities], T.constants(false).sort
    assert_same T, I.const_get(:Touch, false)
    assert_instance_of Module, T
    refute_instance_of Class, T

    %i[TouchPanel TouchCollection TouchLocation GestureSample TouchPanelState]
      .each { |name| refute T.const_defined?(name, false), name.to_s }
    # Touch types must not leak up into Input or Framework.
    %i[TouchLocationState GestureType TouchPanelCapabilities].each do |name|
      refute I.const_defined?(name, false), "Input::#{name}"
      refute F.const_defined?(name, false), "Framework::#{name}"
    end
  end

  def test_gesture_type_is_the_declared_flags_mask_without_invented_composites
    gesture = T::GestureType
    assert_equal true, gesture.instance_variable_get(:@enum_flags)
    assert_equal 0x3FF, gesture.instance_variable_get(:@enum_mask)
    assert_equal 0, gesture::None.to_i

    drag = gesture::HorizontalDrag | gesture::VerticalDrag | gesture::FreeDrag
    assert_instance_of gesture, drag
    assert_equal 56, drag.to_i
    assert_same drag, gesture.coerce(56)
    assert_equal gesture::HorizontalDrag, drag & gesture::HorizontalDrag
    assert_same gesture::None, gesture.coerce(0)

    # XNA declares no All/Drag/Complete aggregate; only the eleven literals exist.
    %i[All Drag DragComplete2 Complete Any Default].reject { |name| name == :DragComplete }
      .each { |name| refute gesture.const_defined?(name, false), name.to_s }
    assert_raises(RangeError) { gesture.coerce(0x400) }
    assert_raises(RangeError) { gesture.coerce(-1) }
  end

  def test_closure_adds_no_native_binding_or_touch_capability_claim
    %w[touch_ gesture_ TOUCH GESTURE].each do |fragment|
      refute CNA::Native::Manifest::CONSTANTS.keys.any? { |name| name.include?(fragment) }, fragment
      refute CNA::Native::Manifest::FUNCTIONS.any? { |entry| entry.symbol.include?(fragment) }, fragment
    end
    assert_equal 38, CNA::Native::Manifest::FUNCTIONS.length
    assert_equal 59, CNA::Native::Manifest::CONSTANTS.length

    capabilities = JSON.parse(Pathname(__dir__).join("..", "docs", "runtime-capabilities.json").read)
    touch = capabilities.fetch("capabilities").find { |row| row.fetch("id") == "input.touch" }
    refute_nil touch
    refute_equal "VERIFIED_NATIVE", touch.fetch("category")
    refute_equal "VERIFIED_NATIVE_ROUTE", touch.fetch("category")
  end
end
