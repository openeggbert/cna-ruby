# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# Foundation 48 — `GameWindow`, and the `Game.Window` it closes.
#
# XNA's `GameWindow` is abstract: ten of its members are `abstract` and exist for a concrete host to
# supply. The canonical C ABI supplies exactly that set, and every one of its routes is addressed
# through the **game** handle — CNA's window has no handle of its own — so this projects as a façade
# over the host rather than a second object with a second lifetime.
class GameWindowTest < Minitest::Test
  F = Microsoft::Xna::Framework
  ROOT = Pathname(__dir__).join("..").expand_path

  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  SIGNATURES = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
                   .fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze

  ROUTES = %w[
    cna_game_set_window_title
    cna_game_window_get_title_size cna_game_window_copy_title
    cna_game_window_get_allow_user_resizing cna_game_window_set_allow_user_resizing
    cna_game_window_get_client_bounds cna_game_window_get_current_orientation
    cna_game_window_get_native_handle_ext
    cna_game_window_get_screen_device_name_size cna_game_window_copy_screen_device_name
    cna_game_window_begin_screen_device_change cna_game_window_end_screen_device_change
    cna_game_window_subscribe
  ].freeze

  def with_window
    game = F::Game.new
    yield game.Window, game
  ensure
    game&.Dispose
  end

  # ------------------------------------------------------------------------- the pinned contract

  def test_it_is_an_abstract_class_over_object_with_twenty_identities
    reference = REFERENCE.fetch("Microsoft.Xna.Framework.GameWindow")
    assert_equal "class", reference.fetch("kind")
    assert_equal "System.Object", reference.fetch("baseType")
    assert_empty reference.fetch("interfaces")
    assert_equal 20, reference.fetch("members").length
    kinds = reference.fetch("members").group_by { |member| member.fetch("kind") }
                     .transform_values(&:length)
    assert_equal({ "method" => 11, "property" => 6, "event" => 3 }, kinds)
    refute_includes STRICT.fetch("missingTypeNames"), "Microsoft.Xna.Framework.GameWindow"
  end

  # XNA declares six event fields; three are `assembly`, so only three are identities. The C ABI
  # defines exactly three `CNA_GAME_WINDOW_EVENT_*` values and they are the same three.
  def test_only_the_three_public_events_are_identities
    events = REFERENCE.fetch("Microsoft.Xna.Framework.GameWindow").fetch("members")
                      .select { |member| member.fetch("kind") == "event" }
                      .map { |member| member.fetch("name") }
    assert_equal %w[ScreenDeviceNameChanged ClientSizeChanged OrientationChanged].sort, events.sort
    events.each { |name| assert F::GameWindow.public_method_defined?(name.to_sym), name }
    %w[Activated Deactivated Paint].each do |internal|
      refute F::GameWindow.public_method_defined?(internal.to_sym), internal
    end
    constants = CNA::Native::Manifest::CONSTANTS.keys.grep(/\ACNA_GAME_WINDOW_EVENT_/)
    assert_equal 3, constants.length
    assert_equal 20, STRICT.fetch("EVENT_IDENTITIES")
    assert_equal 7, STRICT.fetch("EVENT_OWNER_TYPES")
  end

  # `.ctor()` is `assembly`, so construction is private under the Foundation 25 rule.
  def test_construction_is_private
    assert_raises(NoMethodError) { F::GameWindow.new(nil) }
    member = REFERENCE.fetch("Microsoft.Xna.Framework.GameWindow").fetch("members")
                      .find { |entry| entry.fetch("kind") == "constructor" }
    assert_nil member, "the internal constructor is not a selected identity"
  end

  # ------------------------------------------------------------------------- it is one façade

  def test_game_answers_the_same_window_for_its_life
    with_window do |window, game|
      assert_instance_of F::GameWindow, window
      assert_same window, game.Window
      assert_same window, game.Window
    end
  end

  # Every route takes the game handle: there is no window handle in the ABI at all, which is what
  # makes the façade the faithful shape rather than an invented second object.
  def test_every_route_is_addressed_through_the_game_handle
    ROUTES.each do |route|
      entry = CNA::Native::Manifest::FUNCTIONS.find { |function| function.symbol == route }
      refute_nil entry, route
      assert_equal "CNA_Handle", entry.c_arguments.first, route
    end
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    refute(symbols.any? { |symbol| symbol.include?("CNA_GameWindowHandle") })
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
  end

  # ------------------------------------------------------------------------------ Title

  # The abstract constructor sets `title = String.Empty`, but `WindowsGameWindow`'s constructor
  # immediately calls `set_Title(GetDefaultTitleName())`, so what a consumer observes before writing
  # one is the host's default. CNA's default arrives through `CNA_GameCreateInfo::window_title`.
  def test_the_title_is_the_hosts_default_until_written
    with_window do |window, _game|
      assert_equal "CNA-Ruby", window.Title
      window.Title = "Ahoj světe ✓"
      assert_equal "Ahoj světe ✓", window.Title
      assert_equal Encoding::UTF_8, window.Title.encoding
    end
  end

  # `set_Title` throws `ArgumentNullException("value", …)` on null and suppresses a same-value write
  # with `String::op_Inequality` before pushing.
  def test_the_title_setter_refuses_nil_and_suppresses_a_same_value_write
    with_window do |window, _game|
      assert_raises(ArgumentError) { window.Title = nil }
      window.Title = "Stable"
      assert_equal "Stable", window.Title
      assert_equal "Stable", (window.Title = window.Title)
      assert_equal "Stable", window.Title
      window.Title = ""
      assert_equal "", window.Title
    end
  end

  # ------------------------------------------------------------------- the abstract host members

  def test_allow_user_resizing_round_trips_through_the_real_route
    with_window do |window, _game|
      refute window.AllowUserResizing
      assert_equal true, (window.AllowUserResizing = true)
      assert window.AllowUserResizing
      window.AllowUserResizing = false
      refute window.AllowUserResizing
    end
  end

  # HEADLESS has no native window, so the honest answers are a zero rectangle, a zero handle, an
  # empty device name and the default orientation. Not one of them is replaced by an invention.
  def test_the_headless_host_answers_are_reported_rather_than_replaced
    with_window do |window, _game|
      bounds = window.ClientBounds
      assert_instance_of F::Rectangle, bounds
      assert_equal [0, 0, 0, 0], [bounds.X, bounds.Y, bounds.Width, bounds.Height]
      assert_equal 0, window.Handle
      assert_equal "", window.ScreenDeviceName
      assert_equal F::DisplayOrientation::Default, window.CurrentOrientation
    end
  end

  # `ClientBounds` answers a Rectangle by value, so each read is a fresh managed value.
  def test_client_bounds_is_copied_out_rather_than_shared
    with_window do |window, _game|
      first = window.ClientBounds
      refute_same first, window.ClientBounds
    end
  end

  def test_the_screen_device_change_pair_runs
    with_window do |window, _game|
      assert_nil window.BeginScreenDeviceChange(false)
      assert_nil window.EndScreenDeviceChange("")
      assert_nil window.EndScreenDeviceChange("", 640, 480)
      assert_raises(ArgumentError) { window.EndScreenDeviceChange(nil) }
    end
  end

  # ------------------------------------------------------------------------------ the raisers

  def test_the_three_public_raisers_raise_with_the_window_and_empty_args
    with_window do |window, _game|
      { OnScreenDeviceNameChanged: :ScreenDeviceNameChanged,
        OnClientSizeChanged: :ClientSizeChanged,
        OnOrientationChanged: :OrientationChanged }.each do |raiser, event|
        seen = []
        window.__send__(event).add { |sender, args| seen << [sender, args] }
        assert_nil window.__send__(raiser)
        assert_equal 1, seen.length, raiser
        assert_same window, seen.first.first
        assert_same CNA::Runtime::EventArgs::Empty, seen.first.last
      end
    end
  end

  # The other three raisers are identities whose event is `assembly`, so they raise nothing — which
  # is exactly what an absent invocation list does.
  def test_the_three_internal_raisers_exist_and_raise_nothing
    with_window do |window, _game|
      %i[OnActivated OnDeactivated OnPaint].each do |raiser|
        assert_nil window.__send__(raiser)
      end
    end
  end

  # ------------------------------------------------------------------------------- what is refused

  # `SetSupportedOrientations` is `famorassem abstract` and the canonical C ABI exposes no route for
  # it: orientation is readable there and not settable. Declared, and refusing rather than
  # pretending to apply an orientation the runtime never receives.
  def test_set_supported_orientations_refuses_rather_than_pretending
    with_window do |window, _game|
      error = assert_raises(CNA::Runtime::NotSupportedError) do
        window.__send__(:SetSupportedOrientations, F::DisplayOrientation::Portrait)
      end
      assert_match(/no supported-orientation route/, error.message)
    end
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    refute(symbols.any? { |symbol| symbol.include?("supported_orientation") })
  end

  # `SetTitle` is `family`, the push half of `Title=`, so it is not a public identity here.
  def test_the_protected_members_are_protected
    %i[SetTitle SetSupportedOrientations OnActivated OnDeactivated OnPaint
       OnScreenDeviceNameChanged OnClientSizeChanged OnOrientationChanged].each do |name|
      refute F::GameWindow.public_method_defined?(name), name
      assert F::GameWindow.protected_method_defined?(name), name
    end
  end

  # The window belongs to its Game: once the native game is gone the window it names is too.
  def test_a_member_reached_after_disposal_raises
    game = F::Game.new
    window = game.Window
    game.Dispose
    assert_raises(CNA::DisposedObjectError) { window.Title }
    assert_raises(CNA::DisposedObjectError) { window.ClientBounds }
  end

  def test_window_is_owner_thread_bound_and_that_is_recorded
    with_window do |window, _game|
      error = nil
      Thread.new do
        Thread.current.report_on_exception = false
        begin
          window.Title
        rescue Exception => exception
          error = exception
        end
      end.join
      assert_instance_of CNA::OwnerThreadError, error
    end
  end

  # ------------------------------------------------------------------------ Game.Window itself

  def test_game_window_closed_the_member_and_left_only_content
    remainder = STRICT.fetch("partialTypes").fetch("Microsoft.Xna.Framework.Game")
                      .map { |entry| entry.split("::", 2).last.sub(/ \(\d+ overloads?\)\z/, "") }
    assert_equal %w[Content], remainder
    assert_equal 110, STRICT.fetch("MISSING_MEMBER")
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
  end

  # `get_Window` is `host?.Window`, and XNA's null branch is unreachable because its constructor
  # makes the host. This completes that deferred step rather than exposing a nil XNA never shows.
  def test_asking_for_the_window_completes_the_deferred_host_step
    game = F::Game.new
    begin
      assert_nil game.instance_variable_get(:@host)
      refute_nil game.Window
      refute_nil game.instance_variable_get(:@host)
    ensure
      game.Dispose
    end
  end
end
