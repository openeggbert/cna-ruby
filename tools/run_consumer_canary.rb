# frozen_string_literal: true
#
# External consumer canary — Foundations 34-39.
#
#   GEM_HOME=<isolated> GEM_PATH=<isolated> ruby -e 'gem "cna-ruby"; load ARGV[0]' \
#     tools/run_consumer_canary.rb
#
# Runs against the **installed gem only**: no path to the working tree is on the load path, and
# every type is reached through `require "cna"` exactly as a third-party consumer would. It defines
# real Ruby subclasses outside CNA-Ruby and proves the component lifecycle they depend on.
#
# The single most important thing it proves is negative: a subclass that overrides `Update` and
# omits `super` gets **no** base component pass, and the native host does not run one behind it.

abort "the working tree must not be on the load path" if $LOAD_PATH.any? { |path| path.include?("_bindings/cna-ruby/lib") }
require "cna"

F = Microsoft::Xna::Framework
FAILURES = []

def check(label)
  actual = yield
  FAILURES << "#{label}: #{actual.inspect}" unless actual == true
  actual
rescue Exception => error # rubocop:disable Lint/RescueException
  FAILURES << "#{label}: #{error.class}: #{error.message}"
  false
end

puts "gem: #{Gem.loaded_specs.fetch("cna-ruby").full_name} from #{Gem.loaded_specs.fetch("cna-ruby").full_gem_path}"
check("the gem is the installed one, not the working tree") do
  !Gem.loaded_specs.fetch("cna-ruby").full_gem_path.include?("_bindings/cna-ruby")
end

# --------------------------------------------------------------------------- real consumer types

class TestComponent < F::GameComponent
  attr_reader :log

  def initialize(game, label)
    super(game)
    @label = label
    @log = []
  end

  attr_reader :label

  def Initialize
    @log << :initialize
    super
  end

  def Update(game_time)
    @log << :update
    super
  end
end

class TestGame < F::Game
  attr_reader :phases, :log

  def initialize
    super
    @phases = []
    @log = []
    @frames = 0
  end

  def Initialize
    @phases << :initialize
    super
  end

  def Update(game_time)
    @phases << :before_super
    super(game_time)
    @phases << :after_super
    @frames += 1
    self.Exit if @frames >= 2
  end
end

class SuppressingGame < F::Game
  attr_reader :updates

  def initialize
    super
    @updates = 0
    @frames = 0
  end

  def Update(game_time)
    @updates += 1
    @frames += 1
    self.Exit if @frames >= 2
  end
end

# ------------------------------------------------------------------------------ stable identities

game = TestGame.new
check("Components answers the same object every time") { game.Components.equal?(game.Components) }
check("Services answers the same object every time") { game.Services.equal?(game.Services) }
check("Components is a GameComponentCollection") { game.Components.instance_of?(F::GameComponentCollection) }
check("Services is a GameServiceContainer") { game.Services.instance_of?(F::GameServiceContainer) }
check("Components inherits the BCL collection projection") do
  F::GameComponentCollection.superclass == CNA::Runtime::Collection
end
check("two Games never share a collection") { !game.Components.equal?(TestGame.new.Components) }
check("Components starts empty") { game.Components.Count.zero? }
check("Services starts empty") { game.Services.GetService(Comparable).nil? }

# ------------------------------------------------------------------- collection add / remove events

added = []
removed = []
game.Components.ComponentAdded.add { |sender, args| added << [sender.equal?(game.Components), args.GameComponent] }
game.Components.ComponentRemoved.add { |_sender, args| removed << args.GameComponent }

first = TestComponent.new(game, :first)
second = TestComponent.new(game, :second)
game.Components.Add(first)
game.Components.Add(second)

check("ComponentAdded fired twice with the collection as sender") do
  added.length == 2 && added.all?(&:first) && added.map(&:last) == [first, second]
end
check("the collection reports both") { game.Components.Count == 2 && game.Components.Contains(first) }
check("a duplicate component is refused") do
  begin
    game.Components.Add(first)
    false
  rescue ArgumentError
    game.Components.Count == 2
  end
end
check("the indexer is read-only") do
  begin
    game.Components[0] = second
    false
  rescue CNA::Runtime::NotSupportedError
    true
  end
end
check("removing raises ComponentRemoved") do
  game.Components.Remove(second)
  removed == [second] && game.Components.Count == 1
end
game.Components.Add(second)

# ------------------------------------------------------------------- component property events

enabled_changes = []
order_changes = []
first.EnabledChanged.add { |sender, _args| enabled_changes << [sender.equal?(first), first.Enabled] }
first.UpdateOrderChanged.add { |sender, _args| order_changes << [sender.equal?(first), first.UpdateOrder] }

check("defaults are Enabled true and UpdateOrder 0") { first.Enabled == true && first.UpdateOrder.zero? }
check("Game is the one it was constructed with") { first.Game.equal?(game) }
first.Enabled = false
first.Enabled = false
check("EnabledChanged fires once and the handler sees the new value") do
  enabled_changes == [[true, false]]
end
first.Enabled = true
first.UpdateOrder = 5
first.UpdateOrder = 5
check("UpdateOrderChanged fires once and the handler sees the new value") do
  order_changes == [[true, 5]]
end

# ------------------------------------------------------------------------------- update ordering

first.UpdateOrder = 2
second.UpdateOrder = 1
game.Run

check("the game ran both frames") { game.phases.count(:before_super) >= 2 }
check("subclass work happens before and after super") do
  index = game.phases.index(:before_super)
  game.phases[index] == :before_super && game.phases[index + 1] == :after_super
end
check("both components were initialised before the first update") do
  first.log.first == :initialize && second.log.first == :initialize
end
check("both components were updated") do
  first.log.count(:update) >= 1 && second.log.count(:update) >= 1
end
check("the base pass ran once per frame, not twice") do
  first.log.count(:update) == game.phases.count(:before_super)
end
game.Dispose

# ------------------------------------------------------- omitting super suppresses the base pass

suppressing = SuppressingGame.new
lonely = TestComponent.new(suppressing, :lonely)
suppressing.Components.Add(lonely)
suppressing.Run
check("the subclass Update really ran") { suppressing.updates >= 2 }
check("omitting super means the base component pass never runs") { lonely.log.count(:update).zero? }
check("the host did not run the base pass behind the override") { !lonely.log.include?(:update) }
suppressing.Dispose

# --------------------------------------------------------------- add after the game is running

class LateGame < F::Game
  attr_reader :late, :log

  def initialize
    super
    @log = []
    @frames = 0
    @late = nil
  end

  def Update(game_time)
    super(game_time)
    @frames += 1
    if @frames == 1
      @late = TestComponent.new(self, :late)
      self.Components.Add(@late)
    end
    self.Exit if @frames >= 3
  end
end

late_game = LateGame.new
late_game.Run
check("a component added while running is initialised immediately") do
  late_game.late.log.first == :initialize
end
check("and it is updated on later frames") { late_game.late.log.count(:update) >= 1 }
late_game.Dispose

# ------------------------------------------------------------------------------- disposal

owner = TestGame.new
victim = TestComponent.new(owner, :victim)
owner.Components.Add(victim)
disposed = 0
victim.Disposed.add { |sender, _args| disposed += 1 if sender.equal?(victim) }
victim.Dispose
check("disposing a component removes it from Components") { owner.Components.Count.zero? }
check("and raises Disposed once") { disposed == 1 }
victim.Dispose
check("disposing again raises Disposed again: there is no flag") { disposed == 2 }

survivor = TestComponent.new(owner, :survivor)
owner.Components.Add(survivor)
survivor_disposed = 0
survivor.Disposed.add { |_sender, _args| survivor_disposed += 1 }
owner.Dispose
check("Game.Dispose disposes every component it holds") { survivor_disposed == 1 }

# ------------------------------------------------------------------ nothing leaked into the API

check("no IDisposable constant exists anywhere") do
  !Object.const_defined?(:IDisposable, false) &&
    !CNA::Runtime.const_defined?(:IDisposable, false) &&
    !F.const_defined?(:IDisposable, false) &&
    !Object.const_defined?(:System, false)
end
check("no base-call helper was invented") do
  %i[GameBaseUpdate GameBaseDraw GameBaseInitialize].none? { |name| F::Game.method_defined?(name) }
end
check("the collection publishes no mutation that bypasses its hooks") do
  %i[<< push delete_at concat].none? { |name| F::GameComponentCollection.public_method_defined?(name) }
end
check("the lifecycle hooks stay protected") do
  %i[Initialize Update Draw].all? { |name| F::Game.protected_method_defined?(name) }
end

puts FAILURES.empty? ? "CONSUMER_CANARY=pass" : "CONSUMER_CANARY=fail"
FAILURES.each { |failure| puts "  FAILED #{failure}" }
exit(FAILURES.empty? ? 0 : 1)
