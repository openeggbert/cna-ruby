# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"

# Foundation 32 — `TouchPanel`, which closes the whole `Input.Touch` namespace.
#
# The headline fact, and the one every claim here rests on: **the pinned XNA 4.0 Windows
# `Input.Touch` assembly is a stub**. XNA's touch support was for Windows Phone; the Windows
# assembly keeps the shape and answers constants. That is a measurement, not an opinion — the
# hash-admitted IL inventory records `nativeReachable: false` for every type the assembly declares,
# `Touch::WindowHandle` is a plain static field read, and `TouchPanelCapabilities::GetCaps` is
# `initobj; ret`.
#
# So every member is settled by IL rather than by a device, which is exactly why the dependency
# frontier reported the type consumable once the TouchCollection pair existed, and why completing it
# claims no touch hardware.
class TouchPanelTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path

  F = Microsoft::Xna::Framework
  T = Microsoft::Xna::Framework::Input::Touch
  P = T::TouchPanel

  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)
  IL = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read)
  RULES = JSON.parse(ROOT.join("tools", "api_compat", "mapping-rules.json").read)

  # Every test that touches the statics restores them, because they are process-global exactly as
  # the CLR's are.
  def setup
    @saved = %i[@enabled_gestures @gestures_have_been_enabled @window_handle @display_orientation
                @display_width @display_height @display_settings_changed]
             .to_h { |name| [name, P.instance_variable_get(name)] }
  end

  def teardown
    @saved.each { |name, value| P.instance_variable_set(name, value) }
  end

  def enable_gestures = P.EnabledGestures = T::GestureType::Tap

  # ------------------------------------------------------ the assembly is a stub, and it is measured

  def test_no_type_in_the_pinned_touch_assembly_reaches_a_native_entry_point
    touch_types = IL.fetch("types").select do |_name, entry|
      entry.fetch("assembly") == "Microsoft.Xna.Framework.Input.Touch.dll"
    end
    refute_empty touch_types
    touch_types.each do |name, entry|
      refute entry.fetch("nativeReachable"), name
      assert_empty entry.fetch("nativeReachableMethods"), name
      assert_equal "b0585224c18022c3661057ae79544644c10f33f1dc529678364f3d6b25151c25",
                   entry.fetch("assemblySha256"), name
    end
    # And no native symbol was bound for touch.
    assert_equal 39, CNA::Native::Manifest::FUNCTIONS.length
    assert(CNA::Native::Manifest::FUNCTIONS.none? { |name, _| name.to_s.include?("touch") })
  end

  def test_the_namespace_is_complete_and_touch_panel_reports_zero_local_diagnostics
    assert_includes STRICT.fetch("completeTypeNames"), "Microsoft.Xna.Framework.Input.Touch.TouchPanel"
    assert_equal 0, STRICT.fetch("localDiagnostics").fetch("Microsoft.Xna.Framework.Input.Touch.TouchPanel")
    assert_empty STRICT.fetch("missingTypeNames").grep(/\AMicrosoft\.Xna\.Framework\.Input\.Touch\./)
  end

  # --------------------------------------------------------------------------- the static class

  def test_it_projects_as_a_static_class
    assert_instance_of Class, P
    refute P.respond_to?(:new)
    error = assert_raises(TypeError) { P.__send__(:new) }
    assert_equal "TouchPanel is static", error.message
    # Every CLR static member is a Ruby class method, and the type declares no instance surface.
    assert_empty P.public_instance_methods(false)
    %i[GetCapabilities GetState ReadGesture IsGestureAvailable EnabledGestures WindowHandle
       DisplayOrientation DisplayWidth DisplayHeight].each { |name| assert_respond_to P, name }
    %i[EnabledGestures= WindowHandle= DisplayOrientation= DisplayWidth= DisplayHeight=]
      .each { |name| assert_respond_to P, name }
    # IsGestureAvailable is get-only in the reference contract.
    refute P.respond_to?(:IsGestureAvailable=)
  end

  # ------------------------------------------------------------------------------ GetCapabilities

  # `GetCaps` is `initobj; ret` — the CLR default struct value, queried from nothing.
  def test_get_capabilities_answers_the_clr_default_struct_value
    capabilities = P.GetCapabilities
    assert_instance_of T::TouchPanelCapabilities, capabilities
    refute capabilities.IsConnected
    assert_equal 0, capabilities.MaximumTouchCount
    # Returned by value, so each call answers a fresh struct.
    refute_same capabilities, P.GetCapabilities
  end

  # ------------------------------------------------------------------------------------ GetState

  # Both state structs its IL passes to the internal Update are zeroed on every call, for ever, so
  # the result is always an empty collection with the literal `true` connected flag.
  def test_get_state_answers_an_empty_connected_collection
    state = P.GetState
    assert_instance_of T::TouchCollection, state
    assert_equal 0, state.Count
    assert state.IsConnected
    assert state.IsReadOnly
    assert_empty state.to_a
    refute state.GetEnumerator.MoveNext
  end

  def test_get_state_is_stable_and_answers_a_fresh_collection
    first = P.GetState
    second = P.GetState
    refute_same first, second
    assert_equal first.Count, second.Count
    assert_equal first.IsConnected, second.IsConnected
    # Nothing a caller can do changes it: the display settings are the only statics GetState reads,
    # and resetting them changes nothing observable.
    P.DisplayWidth = 480
    P.DisplayHeight = 800
    P.DisplayOrientation = F::DisplayOrientation::Portrait
    assert_equal 0, P.GetState.Count
    assert P.GetState.IsConnected
  end

  # The pair a reader will trip on, asserted together so the reason is on record.
  def test_get_state_reports_connected_while_get_capabilities_reports_disconnected
    assert P.GetState.IsConnected
    refute P.GetCapabilities.IsConnected
  end

  # ----------------------------------------------------------------------------------- gestures

  def test_gestures_start_disabled_and_every_gesture_read_throws
    P.instance_variable_set(:@gestures_have_been_enabled, nil)
    P.instance_variable_set(:@enabled_gestures, nil)
    assert_equal T::GestureType::None, P.EnabledGestures
    assert_raises(RuntimeError) { P.IsGestureAvailable }
    assert_raises(RuntimeError) { P.ReadGesture }
  end

  # Once enabled, IsGestureAvailable answers the literal false and ReadGesture still cannot return.
  def test_once_enabled_no_gesture_is_ever_available
    enable_gestures
    assert_equal T::GestureType::Tap, P.EnabledGestures
    refute P.IsGestureAvailable
    assert_raises(RuntimeError) { P.ReadGesture }
    # Enabling every declared gesture changes nothing.
    P.EnabledGestures = T::GestureType.coerce(0x3FF)
    refute P.IsGestureAvailable
    assert_raises(RuntimeError) { P.ReadGesture }
  end

  def test_enabled_gestures_round_trips_every_declared_combination
    P.EnabledGestures = T::GestureType::None
    assert_equal T::GestureType::None, P.EnabledGestures
    combined = T::GestureType::Tap | T::GestureType::Flick
    P.EnabledGestures = combined
    assert_equal combined, P.EnabledGestures
    P.EnabledGestures = T::GestureType.coerce(0x3FF)
    assert_equal 0x3FF, P.EnabledGestures.value
  end

  # The CLR guard is `value & 0xfffffc00`, and the declared GestureType bits sum to exactly 0x3FF,
  # so GestureType.coerce draws the identical accept/reject boundary. Asserting that equivalence is
  # what makes the setter's missing guard a projection rather than an omission.
  def test_the_gesture_mask_is_exactly_the_declared_bits
    declared = T::GestureType.constants(false).map { |name| T::GestureType.const_get(name, false).value }
    assert_equal 0x3FF, declared.reduce(0) { |mask, value| mask | value }
    assert_raises(RangeError) { P.EnabledGestures = 0x400 }
    assert_raises(RangeError) { P.EnabledGestures = -1 }
    assert_raises(TypeError) { P.EnabledGestures = "Tap" }
    # The rejection is the enum projection's, so the class differs from the CLR's ArgumentException.
    assert_operator RangeError, :<, StandardError
  end

  # ---------------------------------------------------------------- display settings and handle

  def test_display_settings_round_trip
    P.DisplayWidth = 1280
    assert_equal 1280, P.DisplayWidth
    P.DisplayHeight = 720
    assert_equal 720, P.DisplayHeight
    P.DisplayWidth = 0
    assert_equal 0, P.DisplayWidth
    P.DisplayWidth = -5
    assert_equal(-5, P.DisplayWidth, "the setter validates nothing but the Int32 domain")
    assert_raises(TypeError) { P.DisplayWidth = 1.5 }
    assert_raises(RangeError) { P.DisplayHeight = 2**31 }
  end

  # `Helpers::ValidateOrientation` accepts exactly 0, 1, 2 or 4 — one declared value, never a
  # combination, even though DisplayOrientation carries [Flags].
  def test_display_orientation_accepts_one_declared_value_and_never_a_combination
    [F::DisplayOrientation::Default, F::DisplayOrientation::LandscapeLeft,
     F::DisplayOrientation::LandscapeRight, F::DisplayOrientation::Portrait].each do |value|
      P.DisplayOrientation = value
      assert_equal value, P.DisplayOrientation
    end
    assert_equal [0, 1, 2, 4],
                 [F::DisplayOrientation::Default, F::DisplayOrientation::LandscapeLeft,
                  F::DisplayOrientation::LandscapeRight, F::DisplayOrientation::Portrait].map(&:value)

    combined = F::DisplayOrientation::LandscapeLeft | F::DisplayOrientation::Portrait
    assert_equal 5, combined.value
    assert_raises(ArgumentError) { P.DisplayOrientation = combined }
    assert_raises(ArgumentError) do
      P.DisplayOrientation = F::DisplayOrientation::LandscapeLeft | F::DisplayOrientation::LandscapeRight
    end
    assert_equal F::DisplayOrientation::Portrait, P.DisplayOrientation, "a refused set changes nothing"
  end

  # `Touch::WindowHandle` is a static native int with no reader on this profile but the property.
  def test_window_handle_is_a_managed_static_integer
    P.WindowHandle = 0
    assert_equal 0, P.WindowHandle
    P.WindowHandle = 0x1234
    assert_equal 0x1234, P.WindowHandle
    assert_instance_of Integer, P.WindowHandle
    P.WindowHandle = -1
    assert_equal(-1, P.WindowHandle, "System.IntPtr projects to a signed native-width Integer")
    assert_raises(TypeError) { P.WindowHandle = "handle" }
    assert_raises(RangeError) { P.WindowHandle = 1 << 128 }
    # It is a managed field, not a native handle: nothing reads it and no FFI value leaks.
    refute P.WindowHandle.is_a?(Fiddle::Pointer) if defined?(Fiddle)
  end

  # ---------------------------------------------------------- the InvalidOperationException mapping

  def test_invalid_operation_maps_to_runtime_error_and_is_catchable
    assert_equal "RuntimeError",
                 CNA::Runtime::BclProjection::THROWN_EXCEPTIONS.fetch("System.InvalidOperationException")
    assert_includes RULES.fetch("bclProjection").fetch("thrownExceptions"),
                    "System.InvalidOperationException"

    P.instance_variable_set(:@gestures_have_been_enabled, nil)
    caught = begin
      P.ReadGesture
    rescue => error
      error
    end
    assert_instance_of RuntimeError, caught
    assert_operator caught.class, :<, StandardError
    refute_operator caught.class, :<=, ::ScriptError
    # Not the bare root, so the identity survives.
    refute_equal StandardError, caught.class
  end

  # The CLR messages are localized FrameworkResources strings, which are Microsoft's and are not
  # reproduced.
  def test_no_framework_resource_message_is_fabricated
    P.instance_variable_set(:@gestures_have_been_enabled, nil)
    message = begin
      P.ReadGesture
    rescue => error
      error.message
    end
    refute_includes message, "gesture"
    refute_includes message, "Gesture"
    sources = ROOT.join("lib").glob("**/*.rb").map(&:read).join
    ["gestures have not been enabled", "no gesture is available",
     "is not a valid display orientation"].each do |fabricated|
      assert(!sources.downcase.include?(fabricated), fabricated)
    end
  end

  # ------------------------------------------------------------------ nothing reads a device

  def test_touch_panel_claims_no_device
    refute P.GetCapabilities.IsConnected
    assert_equal 0, P.GetCapabilities.MaximumTouchCount
    assert_equal 0, P.GetState.Count
    refute P.respond_to?(:Update)
    refute P.singleton_class.private_method_defined?(:poll)
    # No CNA context is entered and no native call is made by any member.
    source = ROOT.join("lib", "microsoft", "xna", "framework", "input", "touch.rb").read
    refute_includes source, "CNA::Native"
    refute_includes source, "CNA::Runtime::Context"
  end
end
