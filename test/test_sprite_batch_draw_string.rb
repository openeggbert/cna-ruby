# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `SpriteBatch.DrawString` — the first member of this binding that draws **text**, and the one that
# pays off the `SpriteFont` milestone. Six CLR overloads collapse to two Ruby arities.
class SpriteBatchDrawStringTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.SpriteBatch"

  # ------------------------------------------------------------------- the contract, from metadata

  # Six overloads, three shapes, and the collapse that makes two Ruby arities enough: the
  # `StringBuilder` half of each pair is already the same call, because that BCL identity projects
  # to a Ruby `String`.
  def test_the_six_overloads_collapse_to_two_arities
    overloads = REFERENCE.fetch(NAME).fetch("members")
                         .select { |member| member.fetch("name") == "DrawString" }
                         .map { |member| member.fetch("parameters").map { |p| p.fetch("type") } }
    assert_equal 6, overloads.length
    text_types = overloads.map { |types| types[1] }.tally
    assert_equal({ "System.String" => 3, "System.Text.StringBuilder" => 3 }, text_types)
    assert_equal [4, 4, 9, 9, 9, 9], overloads.map(&:length).sort
    # The two nine-argument shapes differ in the scale parameter alone.
    scales = overloads.select { |types| types.length == 9 }.map { |types| types[6] }.uniq.sort
    assert_equal ["Microsoft.Xna.Framework.Vector2", "System.Single"], scales
    assert_equal "String", CNA::Runtime::BclProjection::TYPES.fetch("System.Text.StringBuilder")
  end

  def test_the_scoreboard_records_the_six_and_the_remainder_shrank
    assert_equal ReviewedScoreboard::TARGET_MEMBERS, STRICT.fetch("TARGET_MEMBERS")
    assert_equal ReviewedScoreboard::MISSING_MEMBER, STRICT.fetch("MISSING_MEMBER")
    remainder = ReviewedScoreboard.partial_remainder(STRICT, NAME)
                                  .map { |entry| entry.split("::", 2).last.sub(/ \(\d+ overloads?\)\z/, "") }
    refute_includes remainder, "DrawString"
    # `Begin` and `Draw` were what the type still owed; later milestones closed `Draw` and all but
    # the two `Effect`-taking `Begin` overloads.
    assert_equal %w[Begin], remainder.sort
    assert_equal 28, STRICT.fetch("OVERLOAD_MAPPING_MISMATCH")
  end

  def test_the_route_and_its_layout
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    assert_includes symbols, "cna_sprite_batch_draw_string"
    # `draw_mesh_ext` has no XNA identity and stays unbound.
    refute_includes symbols, "cna_sprite_batch_draw_mesh_ext"
    layout = CNA::Native::Layouts::SpriteTextCommand
    assert_equal 72, layout.size
    assert_equal %w[struct_size struct_version sprite_font text position color rotation origin
                    scale effects layer_depth], layout.fields.map(&:name)
  end

  # ------------------------------------------------------------------------------ live behaviour

  class TextGame < F::Game
    attr_reader :result

    def initialize(&body)
      @body = body
      @result = nil
      super()
      F::GraphicsDeviceManager.new(self)
    end

    def LoadContent
      self.Content.RootDirectory = ENV.fetch("CNA_TEST_XNB_DIR")
      font = self.Content.Load(G::SpriteFont, "Default")
      batch = G::SpriteBatch.new(self.GraphicsDevice)
      @result = @body.call(batch, font)
    ensure
      self.Exit
    end
  end

  def with_batch
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]
    unless ENV["CNA_TEST_XNB_DIR"] && File.directory?(ENV["CNA_TEST_XNB_DIR"].to_s)
      skip "CNA_TEST_XNB_DIR not supplied"
    end

    game = TextGame.new { |batch, font| yield batch, font }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  # Every arity submits, inside an interval, against a real 95-glyph font loaded from MonoGame's own
  # `Default.xnb`.
  def test_each_arity_submits_inside_an_interval
    values = with_batch do |batch, font|
      batch.Begin
      results = []
      results << batch.DrawString(font, "hi", F::Vector2.new(1, 2), F::Color.White)
      results << batch.DrawString(font, "hi", F::Vector2.new(1, 2), F::Color.White,
                                  0.5, F::Vector2.Zero, 2.0, G::SpriteEffects::FlipHorizontally, 0.25)
      results << batch.DrawString(font, "hi", F::Vector2.new(1, 2), F::Color.White,
                                  0.0, F::Vector2.Zero, F::Vector2.new(1, 2), G::SpriteEffects::None, 0.0)
      results << batch.DrawString(font, "", F::Vector2.Zero, F::Color.White)
      batch.End
      results
    end
    assert_equal [nil, nil, nil, nil], values, "every overload returns void"
  end

  # The uniform-scale overload widens its `Single` into both components -- the IL loads `scale`
  # twice into one `Vector2` local -- so the two nine-argument forms really are one call.
  def test_the_single_scale_widens_into_both_components
    values = with_batch do |batch, font|
      batch.Begin
      uniform = batch.DrawString(font, "x", F::Vector2.Zero, F::Color.White,
                                 0.0, F::Vector2.Zero, 3.0, G::SpriteEffects::None, 0.0)
      vector = batch.DrawString(font, "x", F::Vector2.Zero, F::Color.White,
                                0.0, F::Vector2.Zero, F::Vector2.new(3.0, 3.0), G::SpriteEffects::None, 0.0)
      integer = batch.DrawString(font, "x", F::Vector2.Zero, F::Color.White,
                                 0.0, F::Vector2.Zero, 3, G::SpriteEffects::None, 0.0)
      batch.End
      [uniform, vector, integer]
    end
    assert_equal [nil, nil, nil], values
  end

  # `if (spriteFont == null) throw new ArgumentNullException("spriteFont"); if (text == null) …` --
  # the only two things the IL validates, and it validates nothing else.
  def test_the_two_null_checks_are_the_ils_whole_validation
    values = with_batch do |batch, font|
      batch.Begin
      results = [
        (begin; batch.DrawString(nil, "x", F::Vector2.Zero, F::Color.White); nil; rescue => e; e.class; end),
        (begin; batch.DrawString(font, nil, F::Vector2.Zero, F::Color.White); nil; rescue => e; e.class; end),
        (begin; batch.DrawString(font, 42, F::Vector2.Zero, F::Color.White); nil; rescue => e; e.class; end),
        (begin; batch.DrawString(font, "x", F::Vector2.Zero, 0); nil; rescue => e; e.class; end),
        (begin; batch.DrawString(font, "x", F::Vector2.Zero); nil; rescue => e; e.class; end),
        # Non-finite transforms are refused by this binding, as every SpriteBatch submission is.
        (begin
           batch.DrawString(font, "x", F::Vector2.Zero, F::Color.White,
                            Float::INFINITY, F::Vector2.Zero, 1.0, G::SpriteEffects::None, 0.0)
           nil
         rescue => e
           e.class
         end)
      ]
      batch.End
      results
    end
    assert_equal [ArgumentError, ArgumentError, TypeError, TypeError, ArgumentError, RangeError], values
  end

  # The interval rule is this binding's `InvalidBindingStateError`, the same one `Draw` uses, and it
  # is checked before anything else.
  def test_it_requires_an_interval
    values = with_batch do |batch, font|
      outside = begin
        batch.DrawString(font, "x", F::Vector2.Zero, F::Color.White)
        nil
      rescue => error
        error.class
      end
      batch.Begin
      batch.End
      after = begin
        batch.DrawString(font, "x", F::Vector2.Zero, F::Color.White)
        nil
      rescue => error
        error.class
      end
      [outside, after]
    end
    assert_equal [CNA::InvalidBindingStateError] * 2, values
  end

  # A character the font cannot resolve is refused by **CNA**, carrying the message XNA's own
  # `InternalDraw` raises for the same reason. The font really is the 95-glyph ASCII one, so this is
  # a measured refusal rather than an invented rule.
  def test_a_character_the_font_cannot_resolve_is_refused
    values = with_batch do |batch, font|
      batch.Begin
      result = begin
        batch.DrawString(font, "é", F::Vector2.Zero, F::Color.White)
        nil
      rescue => error
        [error.class, error.message]
      end
      batch.End
      [result, font.Characters.Count, font.DefaultCharacter]
    end
    assert_equal CNA::NativeError, values[0][0]
    assert_includes values[0][1], "cannot be resolved by this SpriteFont"
    assert_equal 95, values[1], "MonoGame's Default.xnb is the printable ASCII range"
    assert_nil values[2], "and it declares no DefaultCharacter, so nothing substitutes"
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_adds_no_begin_overload_effect_or_visible_claim
    # The state-bearing Begin overloads arrived in the milestone after this one; what **this** one
    # claimed is that it added none of them, and the two that need an `Effect` are still what
    # `SpriteBatch` owes.
    remainder = ReviewedScoreboard.partial_remainder(STRICT, NAME)
                                  .map { |entry| entry.split("::", 2).last }
    assert_equal ["Begin (2 overloads)"], remainder.sort
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    refute_includes symbols, "cna_sprite_batch_begin_with_states"
    refute G.const_defined?(:Effect, false)
  end
end
