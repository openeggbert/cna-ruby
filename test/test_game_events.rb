# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"

# Foundation 41 — the four canonical Game events.
#
# Every one is `EventHandler`1<EventArgs>`, and each projects to exactly one public Ruby reader over
# CNA::Runtime::Event. Three are raised by CNA's own game-event subscriptions through the protected
# raisers XNA declares; the fourth, `Disposed`, is raised inline by `Dispose`, exactly as the IL
# raises it inline at the end of `Dispose(Boolean)`.
class GameEventsTest < Minitest::Test
  F = Microsoft::Xna::Framework
  ROOT = Pathname(__dir__).join("..").expand_path

  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  SIGNATURES = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
                   .fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze

  IDENTITIES = %i[Activated Deactivated Exiting Disposed].freeze
  RAISERS = %i[OnActivated OnDeactivated OnExiting].freeze

  def game_reference = REFERENCE.fetch("Microsoft.Xna.Framework.Game")

  # ------------------------------------------------------------------------- the pinned contract

  def test_all_four_events_are_the_same_closed_generic_delegate
    events = game_reference.fetch("members").select { |member| member.fetch("kind") == "event" }
    assert_equal IDENTITIES, events.map { |member| member.fetch("name").to_sym }
    events.each do |member|
      assert_equal "System.EventHandler`1[System.EventArgs]", member.fetch("type")
      assert_equal true, member.fetch("add")
      assert_equal true, member.fetch("remove")
      assert_equal false, member.fetch("static")
    end
  end

  # Each raiser takes (object sender, EventArgs args) and is protected. `Disposed` has no raiser at
  # all: the IL raises it inline, which is why this list is three and not four.
  def test_the_three_raisers_are_protected_and_take_sender_and_args
    RAISERS.each do |name|
      member = game_reference.fetch("members").find { |entry| entry.fetch("name") == name.to_s }
      refute_nil member, name
      assert_equal "method", member.fetch("kind")
      assert_equal "protected", member.fetch("access")
      assert_equal %w[System.Object System.EventArgs],
                   member.fetch("parameters").map { |parameter| parameter.fetch("type") }
    end
    refute(game_reference.fetch("members").any? { |member| member.fetch("name") == "OnDisposed" })
  end

  def test_every_identity_is_selected_and_no_longer_missing
    selected = SIGNATURES.fetch("Microsoft.Xna.Framework.Game").fetch("members")
                         .map { |member| member.fetch("name").to_sym }
    (IDENTITIES + RAISERS).each { |name| assert_includes selected, name }
    remainder = STRICT.fetch("partialTypes").fetch("Microsoft.Xna.Framework.Game")
    (IDENTITIES + RAISERS).each do |name|
      refute(remainder.any? { |entry| entry.include?("::#{name} ") }, name)
    end
    assert_equal 17, STRICT.fetch("EVENT_IDENTITIES")
    assert_equal 6, STRICT.fetch("EVENT_OWNER_TYPES")
    assert_equal 0, STRICT.fetch("EVENT_MAPPING_MISMATCH")
    assert_equal 0, STRICT.fetch("UNEXPECTED_MEMBER")
  end

  # ------------------------------------------------------------------------- the Ruby projection

  def test_one_reader_per_event_with_no_writer_and_no_accessor_pair
    game = F::Game.new
    begin
      IDENTITIES.each do |name|
        assert_instance_of CNA::Runtime::Event, game.public_send(name), name
        assert_same game.public_send(name), game.public_send(name), "#{name} must be stable"
        refute_respond_to game, :"#{name}="
        refute_respond_to game, :"add_#{name}"
        refute_respond_to game, :"remove_#{name}"
      end
      assert_equal IDENTITIES, (F::Game.xna_event_identities & IDENTITIES)
    ensure
      game.Dispose
    end
  end

  def test_the_raisers_are_protected_in_ruby_too
    RAISERS.each do |name|
      assert_includes F::Game.protected_instance_methods(false), name
      refute_includes F::Game.public_instance_methods(false), name
    end
  end

  # Readers exist from construction, so a handler may be added long before any host does.
  def test_handlers_may_be_added_before_the_game_has_ever_run
    game = F::Game.new
    begin
      token = game.Activated.add(->(_sender, _args) {})
      refute_nil token
      assert_same token, game.Activated.remove(token)
    ensure
      game.Dispose
    end
  end

  # ------------------------------------------------------- the sender each raiser really passes

  # OnActivated and OnDeactivated load `ldarg.0` -- `this` -- as the delegate's sender and ignore
  # the sender they were given, so calling the base with another sender still raises with the Game.
  def test_activated_and_deactivated_always_raise_with_the_game_itself
    game = F::Game.new
    begin
      seen = []
      game.Activated.add(->(sender, args) { seen << [:Activated, sender, args] })
      game.Deactivated.add(->(sender, args) { seen << [:Deactivated, sender, args] })
      other = Object.new
      game.__send__(:OnActivated, other, CNA::Runtime::EventArgs::Empty)
      game.__send__(:OnDeactivated, other, CNA::Runtime::EventArgs::Empty)
      assert_equal %i[Activated Deactivated], seen.map(&:first)
      seen.each do |_identity, sender, args|
        assert_same game, sender
        assert_same CNA::Runtime::EventArgs::Empty, args
      end
    ensure
      game.Dispose
    end
  end

  # OnExiting loads `ldnull`. XNA really does raise Exiting with a null sender, and a handler
  # written against XNA may test it, so the projection dispatches nil rather than tidying it up.
  def test_exiting_raises_with_a_null_sender
    game = F::Game.new
    begin
      seen = []
      game.Exiting.add(->(sender, args) { seen << [sender, args] })
      game.__send__(:OnExiting, game, CNA::Runtime::EventArgs::Empty)
      assert_equal 1, seen.length
      assert_nil seen[0][0], "XNA's OnExiting loads ldnull as the sender"
      assert_same CNA::Runtime::EventArgs::Empty, seen[0][1]
    ensure
      game.Dispose
    end
  end

  # The args argument is `ldarg.2`, passed through rather than replaced with EventArgs.Empty.
  def test_the_args_argument_is_passed_through_unchanged
    game = F::Game.new
    begin
      args = CNA::Runtime::EventArgs.new
      seen = []
      RAISERS.zip(IDENTITIES).each do |raiser, identity|
        game.public_send(identity).add(->(_sender, received) { seen << received })
        game.__send__(raiser, nil, args)
      end
      assert_equal 3, seen.length
      seen.each { |received| assert_same args, received }
    ensure
      game.Dispose
    end
  end

  # A subclass override runs and `super` runs the base once, which is the whole base-call mechanism
  # here -- no parallel base-call API was invented for the raisers either.
  def test_a_subclass_raiser_override_composes_through_super
    log = []
    klass = Class.new(F::Game) do
      define_method(:OnActivated) do |sender, args|
        log << :before
        super(sender, args)
        log << :after
      end
      protected :OnActivated
    end
    game = klass.new
    begin
      game.Activated.add(->(_sender, _args) { log << :handler })
      game.__send__(:OnActivated, game, CNA::Runtime::EventArgs::Empty)
      assert_equal %i[before handler after], log
    ensure
      game.Dispose
    end
  end

  # -------------------------------------------------------------------------------- Disposed

  def test_dispose_raises_disposed_with_the_game_and_empty_args
    game = F::Game.new
    seen = []
    game.Disposed.add(->(sender, args) { seen << [sender, args] })
    game.Dispose
    assert_equal 1, seen.length
    assert_same game, seen[0][0]
    assert_same CNA::Runtime::EventArgs::Empty, seen[0][1]
  end

  # A Game that never ran has no native host at all, and CNA's own disposed signal only exists once
  # a host does -- so Disposed is raised by Dispose itself rather than relayed. XNA raises it for
  # every disposal, and so does this.
  def test_disposed_is_raised_even_though_no_native_host_was_ever_created
    game = F::Game.new
    assert_nil game.instance_variable_get(:@host)
    raised = 0
    game.Disposed.add(->(_sender, _args) { raised += 1 })
    game.Dispose
    assert_equal 1, raised
    assert_nil game.instance_variable_get(:@host)
  end

  # Recorded deviation: XNA's Dispose(Boolean) has no disposed guard, so a second Dispose() raises
  # Disposed a second time. This binding's Dispose returns early because native destruction is not
  # repeatable, and the event inherits that idempotence rather than introducing it.
  def test_a_second_dispose_raises_nothing_which_is_a_recorded_deviation
    game = F::Game.new
    raised = 0
    game.Disposed.add(->(_sender, _args) { raised += 1 })
    game.Dispose
    game.Dispose
    game.Dispose
    assert_equal 1, raised
  end

  # A handler that raises does not corrupt disposal: the Game is disposed either way, and the
  # exception surfaces rather than being swallowed.
  def test_a_raising_disposed_handler_still_leaves_the_game_disposed
    game = F::Game.new
    game.Disposed.add(->(_sender, _args) { raise "from a Disposed handler" })
    error = assert_raises(RuntimeError) { game.Dispose }
    assert_equal "from a Disposed handler", error.message
    assert game.__send__(:disposed?)
    game.Dispose
  end

  # ------------------------------------------------------------------- what this does not claim

  def test_no_event_is_added_by_the_binding_and_no_activation_is_fabricated
    game = F::Game.new
    begin
      IDENTITIES.each do |name|
        assert_empty game.public_send(name).instance_variable_get(:@handlers), name
      end
    ensure
      game.Dispose
    end
  end

  # `IsActive` is not implied by these events and is not derived from them. XNA's `HostActivated`
  # and `HostDeactivated` write the private `isActive` field and *then* raise; the raisers this
  # binding exposes are the second half only, and the property reads CNA's own focus route. So
  # raising `Activated` by hand -- which a subclass may do, because the raiser is protected and
  # overridable -- must not make the game report itself active. Foundation 45 completed the
  # property; this is the seam between the two that must not close.
  def test_raising_activated_by_hand_does_not_make_the_game_active
    game = F::Game.new
    begin
      game.Tick
      refute game.IsActive
      seen = []
      game.Activated.add { |sender, _args| seen << sender }
      game.__send__(:OnActivated, game, CNA::Runtime::EventArgs::Empty)
      assert_equal [game], seen
      refute game.IsActive, "the event is an observation, not the state"
    ensure
      game.Dispose
    end
  end
end
