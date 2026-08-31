# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"

# Foundation 45 — `Game.IsActive`.
#
# The property that earlier handoffs deferred because "XNA's property is `isActive &&
# !Guide.IsVisible`, and the projection would claim a property whose defining subtlety it cannot
# observe". It can: all three terms of the pinned expression have exactly one canonical CNA route,
# so the exact expression is implemented rather than approximated.
class GameIsActiveTest < Minitest::Test
  F = Microsoft::Xna::Framework
  ROOT = Pathname(__dir__).join("..").expand_path

  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  SIGNATURES = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
                   .fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze

  ROUTES = %w[
    cna_game_get_is_active
    cna_guide_get_is_visible
    cna_gamer_services_dispatcher_get_is_initialized
  ].freeze

  def with_game(klass = F::Game)
    game = klass.new
    yield game
  ensure
    game&.Dispose
  end

  # ------------------------------------------------------------------------- the pinned contract

  def test_is_active_is_a_public_get_only_boolean_instance_property
    member = REFERENCE.fetch("Microsoft.Xna.Framework.Game").fetch("members")
                      .find { |entry| entry.fetch("name") == "IsActive" }
    refute_nil member
    assert_equal "property", member.fetch("kind")
    assert_equal "System.Boolean", member.fetch("type")
    assert_equal true, member.fetch("get")
    assert_equal false, member.fetch("set")
    assert_equal "public", member.fetch("getAccess")
    assert_nil member.fetch("setAccess")
    assert_equal false, member.fetch("static")
  end

  def test_it_is_selected_read_only_and_no_longer_missing
    selected = SIGNATURES.fetch("Microsoft.Xna.Framework.Game").fetch("members")
                         .find { |member| member.fetch("name") == "IsActive" }
    refute_nil selected
    assert_equal false, selected.fetch("set")
    refute F::Game.method_defined?(:IsActive=), "the contract declares no setter"
    remainder = STRICT.fetch("partialTypes").fetch("Microsoft.Xna.Framework.Game")
    refute(remainder.any? { |entry| entry.include?("::IsActive ") }, remainder.inspect)
    assert_equal 115, STRICT.fetch("MISSING_MEMBER")
  end

  # Neither `Guide` nor `GamerServicesDispatcher` is in the selected profile — the whole
  # GamerServices namespace contributes exactly one type, `GamerServicesComponent`, and it is still
  # missing. Reading their canonical routes projects no type and invents no constant.
  def test_no_gamer_services_type_is_invented
    gamer_services = REFERENCE.keys.select { |name| name.include?("GamerServices") }
    assert_equal ["Microsoft.Xna.Framework.GamerServices.GamerServicesComponent"], gamer_services
    assert_includes STRICT.fetch("missingTypeNames"), gamer_services.first
    refute F.const_defined?(:GamerServices, false)
    refute F::Game.const_defined?(:Guide, false)
    refute Object.const_defined?(:System)
  end

  # ------------------------------------------------------------------------------- the three routes

  def test_all_three_terms_are_bound_canonical_routes
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    ROUTES.each { |route| assert_includes symbols, route }
    assert_equal 55, CNA::Native::Manifest::FUNCTIONS.length
  end

  # The two GamerServices routes project CLR statics, so neither takes a handle.
  def test_the_two_gamer_services_routes_are_process_global
    ROUTES.drop(1).each do |route|
      entry = CNA::Native::Manifest::FUNCTIONS.find { |function| function.symbol == route }
      assert_equal ["CNA_Bool"], entry.c_arguments
      assert_match(/PROCESS_GLOBAL/, entry.ownership)
    end
    game_route = CNA::Native::Manifest::FUNCTIONS.find { |function| function.symbol == ROUTES.first }
    assert_equal %w[CNA_Handle CNA_Bool], game_route.c_arguments
  end

  # They really answer with no Game in the process, which is what makes the IL's evaluation order
  # — both GamerServices terms first, `isActive` second — projectable as written.
  def test_the_gamer_services_routes_answer_without_a_game
    library = CNA::Native.library
    ROUTES.drop(1).each do |route|
      output = library.pointer_for("C", 0)
      assert_equal 0, library.call(route, output)
    end
  end

  # ------------------------------------------------------------------------------- what it answers

  # XNA's `isActive` is a CLR Boolean field at its default, so a Game that has never run is not
  # active — and asking must not conjure a native game, because the pinned getter allocates nothing.
  def test_a_game_that_never_ran_is_inactive_and_stays_hostless
    with_game do |game|
      refute game.IsActive
      assert_nil game.instance_variable_get(:@host)
    end
  end

  def test_it_is_answerable_off_the_owner_thread_while_no_host_exists
    with_game do |game|
      assert_equal false, Thread.new { game.IsActive }.value
    end
  end

  # A host without a loop has no focus, which CNA reports and this does not embellish.
  def test_a_host_that_never_ran_is_inactive
    with_game do |game|
      game.Tick
      refute_nil game.instance_variable_get(:@host)
      refute game.IsActive
    end
  end

  # The measured transition. XNA's `HostActivated` writes `isActive = true` **before** raising
  # `OnActivated`, so the property is already true inside the handler; CNA's route agrees.
  def test_a_real_run_is_active_from_inside_the_activated_handler_onwards
    seen = []
    runner = Class.new(F::Game) do
      define_method(:Update) do |_time|
        seen << [:update, self.IsActive]
        self.Exit if seen.count { |entry| entry.first == :update } >= 2
      end
      define_method(:Draw) { |_time| seen << [:draw, self.IsActive] }
      define_method(:OnActivated) do |sender, args|
        seen << [:Activated, self.IsActive]
        super(sender, args)
      end
    end
    with_game(runner) do |game|
      game.Run
      assert_equal [:Activated, true], seen.first
      assert(seen.all? { |_name, active| active }, seen.inspect)
      assert game.IsActive, "the flag is not cleared when the loop exits"
    end
  end

  # ------------------------------------------------------------------------------- refused states

  def test_off_the_owner_thread_with_a_host_it_raises
    with_game do |game|
      game.Tick
      error = nil
      Thread.new do
        Thread.current.report_on_exception = false
        begin
          game.IsActive
        rescue Exception => exception
          error = exception
        end
      end.join
      assert_instance_of CNA::OwnerThreadError, error
    end
  end

  # Recorded deviation: XNA's field survives disposal and still answers. There is no native game
  # left to ask here, and answering a fabricated false would be worse than raising.
  def test_a_disposed_game_raises_rather_than_answering
    game = F::Game.new
    game.Dispose
    assert_raises(CNA::DisposedObjectError) { game.IsActive }
  end

  # ------------------------------------------------------------------- the guide term is not dead

  # The guide branch cannot be *observed* in the reviewed artifact: `cna_guide_set_is_visible` is
  # accepted and never reflected by `cna_guide_get_is_visible`, so CNA never reports a visible
  # guide. That is a fact about the runtime, and it is exactly why the expression must be proved
  # wired rather than assumed correct. These two rows drive the private route readers directly and
  # qualify the mapping, not the runtime.
  def test_the_expression_is_the_pinned_truth_table
    table = {
      # [dispatcher initialized, guide visible, native isActive] => IsActive
      [false, false, false] => false,
      [false, false, true] => true,
      [false, true, true] => true,      # the guide is not consulted at all when uninitialized
      [true, false, true] => true,
      [true, true, true] => false,      # the only case the guide term decides
      [true, true, false] => false
    }
    table.each do |(initialized, guide, active), expected|
      with_game do |game|
        game.Tick
        stub_routes(game, initialized: initialized, guide: guide, active: active)
        assert_equal expected, game.IsActive, [initialized, guide, active].inspect
      end
    end
  end

  # And the guide route really is only asked when the dispatcher says it may be: XNA guards because
  # `Guide.get_IsVisible` throws `InvalidOperationException` otherwise.
  def test_the_guide_route_is_not_read_while_the_dispatcher_is_uninitialized
    asked = []
    with_game do |game|
      game.Tick
      stub_routes(game, initialized: false, guide: false, active: true, log: asked)
      assert game.IsActive
      refute_includes asked, "cna_guide_get_is_visible"
      assert_includes asked, "cna_gamer_services_dispatcher_get_is_initialized"
    end
  end

  private

  def stub_routes(game, initialized:, guide:, active:, log: [])
    answers = {
      "cna_gamer_services_dispatcher_get_is_initialized" => initialized,
      "cna_guide_get_is_visible" => guide,
      "cna_game_get_is_active" => active
    }
    game.define_singleton_method(:read_native_flag) do |symbol, *_arguments|
      log << symbol
      answers.fetch(symbol)
    end
    game.singleton_class.send(:private, :read_native_flag)
  end
end
