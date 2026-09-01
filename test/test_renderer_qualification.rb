# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "renderer_environment"
require_relative "../lib/cna"

# Native frontier 6 — the qualification against a renderer that really renders.
#
# `docs/generated/renderer-native-report.json` is produced by `tools/run_renderer_qualification.rb`,
# which the ordinary suite does not invoke. That is exactly the shape of the staleness defect
# Foundation 70 found in the dependency frontier — a generated report nothing re-derived, asserted
# against itself for a whole milestone — so this file guards it the same way: every claim is checked
# against the artifact actually loaded now, and the entry for a *different* renderer is checked for
# internal consistency rather than taken on trust.
class RendererQualificationTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path
  REPORT_PATH = ROOT.join("docs", "generated", "renderer-native-report.json")
  REPORT = JSON.parse(REPORT_PATH.read).freeze

  # CNA's own list of the renderers whose descriptors set `needsWindow = false`.
  WINDOWLESS = %w[HEADLESS SOFTWARE STUB PORTABLEGL].freeze

  def runs = REPORT.fetch("runs")

  # ------------------------------------------------------------------------------- the report shape

  def test_the_report_is_native_evidence_and_never_behaviour_authority
    assert_equal 1, REPORT.fetch("schemaVersion")
    assert REPORT.fetch("CNA_NATIVE_EVIDENCE"), "everything here is CNA output"
    refute_empty runs
  end

  # The whole point of the milestone: two artifacts, one of which really rasterises.
  def test_both_qualified_artifacts_are_recorded_and_differ_only_in_the_renderer
    assert_equal %w[HEADLESS OPENGL33], runs.keys.sort
    paths = runs.values.map { |run| run.fetch("artifact").fetch("path") }
    assert_equal 2, paths.uniq.length
    digests = runs.values.map { |run| run.fetch("artifact").fetch("sha256") }
    assert_equal 2, digests.uniq.length
    assert(digests.all? { |digest| digest.match?(/\A[0-9a-f]{64}\z/) })
  end

  # ------------------------------------------------------------- the fact every branch depends on

  # The staleness guard: what the report says about *this* artifact must be what this artifact says
  # about itself, right now.
  def test_the_entry_for_the_loaded_artifact_agrees_with_the_live_measurement
    skip "CNA_NATIVE_LIBRARY not supplied" unless RendererEnvironment.available?

    name = RendererEnvironment.renderer_name
    run = runs[name]
    skip "no recorded run for the loaded renderer #{name.inspect}" if run.nil?

    assert_equal name, run.fetch("renderer").fetch("rendererName")
    assert_equal RendererEnvironment.window_system, run.fetch("renderer").fetch("nativeWindowSystem")
    assert_equal RendererEnvironment.windowed?, run.fetch("renderer").fetch("nativeWindowSystem") != 0
    assert_equal ENV.fetch("CNA_NATIVE_LIBRARY"), run.fetch("artifact").fetch("path")
  end

  # ------------------------------------------------------------------- the real graphics semantic

  # Create, bind, clear, unbind, read. The colour is not a round number in any channel by accident:
  # 0.25/0.5/0.75 land on 64/128/191, which no clear-to-black, clear-to-white or untouched buffer
  # can produce.
  #
  # The rule is written once, as a function of the recorded run, so the mutation control at the
  # bottom can run the same function against a planted defect and require it to complain.
  def self.render_target_findings(name, run, windowless)
    target = run.fetch("renderTarget")
    findings = []
    findings << "#{name}: no render target was created" unless target.fetch("created")
    findings << "#{name}: bind failed" unless target.fetch("bindResult").zero?
    findings << "#{name}: clear failed" unless target.fetch("clearResult").zero?
    findings << "#{name}: the frame is not uniform" unless target.fetch("allPixelsEqual")
    if windowless
      # Honest refusal rather than a fabricated frame: CNA_RESULT_NOT_SUPPORTED, and the caller's
      # buffer left exactly as it was.
      findings << "#{name}: a windowless renderer answered a readback" unless target.fetch("readResult") == 6
      findings << "#{name}: a windowless renderer produced pixels" unless target.fetch("firstPixel") == [0, 0, 0, 0]
    else
      findings << "#{name}: the readback failed" unless target.fetch("readResult").zero?
      findings << "#{name}: the frame is not the colour it was cleared to" unless
        target.fetch("firstPixel") == target.fetch("clearedTo")
      findings << "#{name}: the wrong number of elements was written" unless target.fetch("elementsWritten") == 32
    end
    findings
  end

  def self.frame_findings(name, run)
    run.fetch("frames").flat_map do |length, frames|
      findings = []
      findings << "#{name} #{length}: #{frames["error"]}" unless frames.fetch("error").nil?
      findings << "#{name} #{length}: #{frames.fetch("completed")} of #{frames.fetch("requested")}" unless
        frames.fetch("completed") == frames.fetch("requested")
      findings
    end
  end

  # `docs/graphics-adapter-ordering-upstream-defect.md`. Recorded as a fact of the artifact rather
  # than argued: on a build with a real window, two canonical routes disagree in one frame about
  # whether this host has a display.
  def self.conflict_findings(name, run, windowless)
    conflict = run.fetch("displayEvidenceConflict")
    findings = []
    findings << "#{name}: the adapter is no longer the no-display fallback" unless
      conflict.fetch("adapterIsTheNoDisplayFallback")
    findings << "#{name}: cna_graphics_adapters_refresh no longer refuses" unless conflict.fetch("refreshRefused")
    findings << "#{name}: window surface disagrees with the renderer's own kind" unless
      conflict.fetch("windowHasANativeSurface") == !windowless
    findings << "#{name}: the adapter/window contradiction is not recorded" unless
      conflict.fetch("adapterContradictsTheWindow") == !windowless
    findings
  end

  def self.window_findings(name, run, windowless)
    renderer = run.fetch("renderer")
    system = renderer.fetch("nativeWindowSystem")
    bounds = renderer.fetch("clientBounds")
    findings = []
    if windowless
      findings << "#{name}: a windowless renderer reported a window system" unless system.zero?
      findings << "#{name}: a windowless renderer reported client bounds" unless bounds == [0, 0, 0, 0]
      findings << "#{name}: a windowless renderer reported a display pointer" if
        renderer.fetch("nativeWindowHasDisplayPointer")
    else
      findings << "#{name}: a windowed renderer reported no window system" if system.zero?
      findings << "#{name}: a windowed renderer reported an empty client rectangle" unless
        bounds[2].positive? && bounds[3].positive?
    end
    findings
  end

  def findings_for(name, run)
    windowless = WINDOWLESS.include?(name)
    self.class.window_findings(name, run, windowless) +
      self.class.render_target_findings(name, run, windowless) +
      self.class.frame_findings(name, run) +
      self.class.conflict_findings(name, run, windowless)
  end

  def test_every_recorded_run_satisfies_every_rule
    runs.each { |name, run| assert_empty findings_for(name, run), name }
  end

  def test_a_windowed_renderer_reads_a_cleared_render_target_back_exactly
    windowed = runs.fetch("OPENGL33").fetch("renderTarget")
    assert_equal 0, windowed.fetch("readResult")
    assert_equal [64, 128, 191, 255], windowed.fetch("clearedTo")
    assert_equal [64, 128, 191, 255], windowed.fetch("firstPixel")
    assert_equal 32, windowed.fetch("elementsWritten")

    headless = runs.fetch("HEADLESS").fetch("renderTarget")
    assert_equal 6, headless.fetch("readResult"), "CNA_RESULT_NOT_SUPPORTED, honestly"
    assert_equal [0, 0, 0, 0], headless.fetch("firstPixel")
  end

  def test_every_artifact_survives_sixty_and_six_hundred_frames
    runs.each do |name, run|
      assert_equal 60, run.fetch("frames").fetch("short").fetch("requested"), name
      assert_equal 600, run.fetch("frames").fetch("long").fetch("requested"), name
    end
  end

  # The branch every environment-dependent expectation turns on is measured twice, from two
  # unrelated routes: `cna_game_window_get_native_window_ext`'s window kind, and the window's own
  # client rectangle. If they ever disagree, the six tests that branch on the first one are asserting
  # something other than what they say.
  def test_the_environment_branch_agrees_with_a_second_independent_route
    skip "CNA_NATIVE_LIBRARY not supplied" unless RendererEnvironment.available?

    game = Microsoft::Xna::Framework::Game.new
    begin
      bounds = game.Window.ClientBounds
      assert_equal RendererEnvironment.windowed?, bounds.Width.positive?
      assert_equal RendererEnvironment.windowed?, bounds.Height.positive?
      assert_equal RendererEnvironment.windowed?, !game.Window.Handle.zero?
    ensure
      game.Dispose
    end
  end

  # ------------------------------------------------------------------- the upstream defect it found

  def test_the_adapter_contradicts_the_window_on_a_windowed_renderer
    conflict = runs.fetch("OPENGL33").fetch("displayEvidenceConflict")
    assert conflict.fetch("windowHasANativeSurface")
    assert conflict.fetch("adapterIsTheNoDisplayFallback")
    assert conflict.fetch("adapterContradictsTheWindow")
    assert conflict.fetch("refreshRefused")
    refute_equal conflict.fetch("windowReportsADisplayNamed"), conflict.fetch("adapterReportsDescription")
  end

  # It is not the renderer selection, which is what this repository recorded for several milestones,
  # so the two documents that say so must both be present and must say it.
  def test_the_defect_is_documented_and_the_superseded_reason_is_named
    defect = ROOT.join("docs", "graphics-adapter-ordering-upstream-defect.md").read
    assert_includes defect, "getDefaultAdapterProperty"
    assert_includes defect, "cna_graphics_adapters_refresh"
    assert_includes defect, "UPSTREAM_CNA_BLOCKED"

    qualification = ROOT.join("docs", "real-renderer-qualification-evidence.md").read
    assert_includes qualification, "needsWindow"
    assert_includes qualification, "64,128,191,255"

    registry = JSON.parse(ROOT.join("docs", "runtime-capabilities.json").read).fetch("capabilities")
    adapter = registry.find { |row| row.fetch("id") == "display.adapter-enumeration" }
    assert_equal "UPSTREAM_CNA_BLOCKED", adapter.fetch("category")
    renderer = registry.select { |row| row.fetch("category") == "VERIFIED_NATIVE_RENDERER" }
    assert_equal %w[renderer.frame-stability renderer.native-window renderer.real-rasterization],
                 renderer.map { |row| row.fetch("id") }.sort
  end

  # ------------------------------------------------------------------------------ mutation control

  # A guard nobody has seen fail is not evidence. Each of these plants one defect in a copy of the
  # real run and requires the *same* rule the passing test uses to name it.
  MUTATIONS = {
    "a fabricated frame where the renderer produced none" =>
      { "renderTarget" => { "firstPixel" => [0, 0, 0, 0] } },
    "a windowed renderer recorded as windowless" =>
      { "renderer" => { "nativeWindowSystem" => 0, "clientBounds" => [0, 0, 0, 0] } },
    "the upstream defect quietly declared fixed" =>
      { "displayEvidenceConflict" => { "adapterContradictsTheWindow" => false } },
    "a short run passed off as the long one" =>
      { "frames" => { "long" => { "completed" => 59 } } },
    "a readback that failed reported as a pass" =>
      { "renderTarget" => { "readResult" => 6 } },
    "a clear that did not happen" =>
      { "renderTarget" => { "clearResult" => 3 } }
  }.freeze

  def test_every_guard_fails_on_its_own_planted_defect
    MUTATIONS.each do |description, mutation|
      mutated = deep_merge(runs.fetch("OPENGL33"), mutation)
      refute_empty findings_for("OPENGL33", mutated), description
    end
    # And the control: the unmutated run passes the same rule.
    assert_empty findings_for("OPENGL33", runs.fetch("OPENGL33"))
  end

  private

  def deep_merge(left, right)
    left.merge(right) do |_key, a, b|
      a.is_a?(Hash) && b.is_a?(Hash) ? deep_merge(a, b) : b
    end
  end
end
