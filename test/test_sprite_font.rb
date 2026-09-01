# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `Graphics.SpriteFont`, measured against MonoGame's `Default.xnb` — a real 95-glyph font already in
# the configured `CNA_TEST_XNB_DIR`.
#
# It is the first candidate a **BCL decision** really unblocked. It carried both `BCL_PROJECTION` and
# `NATIVE_RUNTIME`, and every earlier doubly blocked candidate was resolved by building the type its
# IL reached; here that type, `SpriteBatch`, was already complete, so what remained was three
# projections: `System.Char`, `Nullable`1` and `System.Text.StringBuilder`.
class SpriteFontTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.SpriteFont"

  # ------------------------------------------------------------------- the contract, from metadata

  def test_the_contract_is_six_identities_over_two_overloads
    contract = REFERENCE.fetch(NAME)
    assert contract.fetch("sealed")
    assert_equal 6, contract.fetch("members").length
    measure = contract.fetch("members").select { |m| m.fetch("name") == "MeasureString" }
    assert_equal 2, measure.length, "String and StringBuilder"
    assert_equal [["System.String"], ["System.Text.StringBuilder"]],
                 measure.map { |m| m.fetch("parameters").map { |p| p.fetch("type") } }
    # No constructor, and no Dispose: XNA's SpriteFont is not IDisposable.
    assert_empty contract.fetch("members").select { |m| m.fetch("kind") == "constructor" }
    assert_empty contract.fetch("interfaces")
    assert_raises(NoMethodError) { G::SpriteFont.new(nil, 0, 0) }
    assert_equal %i[Characters DefaultCharacter DefaultCharacter= LineSpacing LineSpacing=
                    MeasureString Spacing Spacing=], G::SpriteFont.public_instance_methods(false).sort
  end

  def test_the_scoreboard_records_it_complete_and_the_frontier_lost_it
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_includes STRICT.fetch("completeTypeNames"), NAME
    refute_includes FRONTIER.fetch("dependencyCompleteCandidates").map { |c| c.fetch("name") }, NAME
    assert_equal ReviewedScoreboard::BCL_PROJECTED_IDENTITIES, STRICT.fetch("BCL_PROJECTED_IDENTITIES")
  end

  # `System.Char` is a UTF-16 **code unit**, not a character, which is why it projects to Integer
  # rather than to a one-character String: `0xD800` is a valid Char and not a valid Ruby character.
  def test_the_three_bcl_decisions_this_type_forced
    types = CNA::Runtime::BclProjection::TYPES
    assert_equal "Integer", types.fetch("System.Char")
    assert_equal "NilClass", types.fetch("System.Nullable`1")
    assert_equal "String", types.fetch("System.Text.StringBuilder")
    # And the rules file agrees, which is what keeps the register from being prose.
    rules = JSON.parse(ROOT.join("tools", "api_compat", "mapping-rules.json").read)
    assert_equal types.transform_keys(&:to_s), rules.fetch("bclProjection").fetch("types")
  end

  # ------------------------------------------------------------------------------ live behaviour

  class Host < F::Game
    attr_reader :result

    def initialize(&body)
      @body = body
      @result = nil
      super()
      F::GraphicsDeviceManager.new(self)
    end

    def LoadContent
      self.Content.RootDirectory = ENV.fetch("CNA_TEST_XNB_DIR")
      @result = @body.call(self.Content.Load(G::SpriteFont, "Default"))
    ensure
      self.Exit
    end
  end

  def with_font
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]
    directory = ENV["CNA_TEST_XNB_DIR"]
    skip "CNA_TEST_XNB_DIR not supplied" unless directory && File.file?(File.join(directory, "Default.xnb"))

    game = Host.new { |font| yield font }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  # `ContentManager.Load<SpriteFont>` is XNA's only producer, and it is this binding's too.
  def test_the_content_manager_is_the_only_producer_and_it_really_loads_the_font
    values = with_font do |font|
      [font.class, font.LineSpacing, font.Spacing, font.DefaultCharacter, font.Characters.Count]
    end
    assert_equal G::SpriteFont, values[0]
    assert_operator values[1], :>, 0
    assert_in_delta 0.0, values[2], 0.0001
    assert_nil values[3], "this font declares no fallback character"
    assert_equal 95, values[4], "MonoGame's Default.xnb carries printable ASCII"
  end

  # `get_Characters` builds the `ReadOnlyCollection` once and caches it, so every call answers the
  # **same** object. The map must be sorted, because `GetIndexForCharacter` binary-searches it —
  # asserted rather than assumed.
  def test_characters_is_one_cached_sorted_read_only_collection_of_code_units
    values = with_font do |font|
      chars = font.Characters
      [chars.class, chars.equal?(font.Characters), chars.Count,
       (0...chars.Count - 1).all? { |i| chars[i] < chars[i + 1] },
       chars[0], chars[chars.Count - 1], chars.map(&:class).uniq,
       chars.respond_to?(:Add)]
    end
    assert_equal CNA::Runtime::ReadOnlyCollection, values[0]
    assert_equal true, values[1], "the IL caches it in a field"
    assert_equal true, values[3], "sorted, which is what the binary search requires"
    assert_equal [32, 126], values[4..5], "space through tilde"
    assert_equal [Integer], values[6], "code units, not one-character Strings"
    assert_equal false, values[7]
  end

  # The whole of `InternalMeasure`, and the projection is compared with CNA's own
  # `cna_sprite_font_measure_utf8` rather than only with itself.
  def test_measure_string_reproduces_the_il_and_agrees_with_cnas_own_measurement
    values = with_font do |font|
      native = lambda do |text|
        view = CNA::Native::Layouts::StringView.new(text.b)
        out = CNA::Native.library.pointer_for("Q", 0)
        CNA::Native.library.call("cna_sprite_font_measure_utf8", font.__send__(:native_handle),
                                 view.read_u64(0), view.read_u64(8), out)
        out[0, 8].unpack("ee")
      end
      ["", "A", "Hello", "Hello World", "  ", "~"].to_h do |text|
        measured = font.MeasureString(text)
        [text, [[measured.X, measured.Y], native.call(text)]]
      end
    end
    values.each do |text, (projected, native)|
      assert_equal native, projected,
                   "MeasureString(#{text.inspect}) must agree with cna_sprite_font_measure_utf8"
    end
    assert_equal [0.0, 0.0], values.fetch("")[0], "an empty string measures Vector2.Zero"
    assert_operator values.fetch("Hello World")[0][0], :>, values.fetch("Hello")[0][0]
  end

  # `'\r'` is skipped outright and `'\n'` starts a line; the height is
  # `max(lineSpacing, croppingHeight) + lineBreaks * lineSpacing`, so two lines are taller than one
  # by exactly one `LineSpacing` and no wider than the widest line.
  def test_line_breaks_use_the_il_arithmetic
    values = with_font do |font|
      one = font.MeasureString("A")
      two = font.MeasureString("A\nB")
      crlf = font.MeasureString("A\r\nB")
      bare_cr = font.MeasureString("A\rB")
      wide = font.MeasureString("A\nHello World")
      [font.LineSpacing, [one.X, one.Y], [two.X, two.Y], [crlf.X, crlf.Y],
       [bare_cr.X, bare_cr.Y], [wide.X, wide.Y], [font.MeasureString("AB").X, font.MeasureString("AB").Y]]
    end
    spacing, one, two, crlf, bare_cr, wide, ab = values

    assert_in_delta one[1] + spacing, two[1], 0.001, "one more line is exactly one LineSpacing taller"
    assert_equal two, crlf, "a carriage return is skipped outright"
    assert_equal ab, bare_cr, "so \\r alone does not break a line"
    assert_operator wide[0], :>, two[0], "the width is the widest line"
    assert_in_delta one[1] + spacing, wide[1], 0.001
  end

  # `GetIndexForCharacter` falls back to `DefaultCharacter` once and then raises
  # `ArgumentException(CharacterNotInFont)`; `set_DefaultCharacter` refuses a character the font does
  # not define, and clearing it is always allowed.
  def test_the_default_character_fallback_and_its_refusals
    values = with_font do |font|
      err = ->(&block) { begin; block.call; :ok; rescue => e; e.class; end }
      before = err.call { font.MeasureString("é") }
      font.DefaultCharacter = 63
      set = font.DefaultCharacter
      after = font.MeasureString("é")
      question = font.MeasureString("?")
      refused = err.call { font.DefaultCharacter = 0x00e9 }
      wrong_type = err.call { font.DefaultCharacter = "?" }
      out_of_range = err.call { font.DefaultCharacter = 0x1_0000 }
      font.DefaultCharacter = nil
      [before, set, [after.X, after.Y], [question.X, question.Y], refused, wrong_type,
       out_of_range, font.DefaultCharacter,
       err.call { font.MeasureString("é") }]
    end
    assert_equal ArgumentError, values[0], "no fallback, so a missing character raises"
    assert_equal 63, values[1], "a code unit, not a String"
    assert_equal values[3], values[2], "and with a fallback it measures as that character"
    assert_equal ArgumentError, values[4], "a character the font does not define is refused"
    assert_equal TypeError, values[5]
    assert_equal TypeError, values[6]
    assert_nil values[7], "clearing is always allowed"
    assert_equal ArgumentError, values[8]
  end

  # `set_LineSpacing` and `set_Spacing` are bare field writes — four IL instructions each, with no
  # validation at all — and both really change what `MeasureString` answers.
  def test_the_two_scalar_setters_have_no_validation_and_change_the_measurement
    values = with_font do |font|
      base = font.MeasureString("AB")
      font.LineSpacing = 40
      line_spacing = font.LineSpacing
      tall = font.MeasureString("A\nB")
      font.Spacing = 2.5
      spacing = font.Spacing
      spaced = font.MeasureString("AB")
      wrong_type = begin; font.LineSpacing = "40"; :ok; rescue => e; e.class; end
      negative = begin; font.LineSpacing = -5; font.LineSpacing; rescue => e; e.class; end
      nan = begin; font.Spacing = Float::NAN; :ok; rescue => e; e.class; end
      [[base.X, base.Y], line_spacing, [tall.X, tall.Y], spacing, [spaced.X, spaced.Y],
       negative, nan, wrong_type]
    end
    base, line_spacing, tall, spacing, spaced, negative, nan, wrong_type = values

    assert_equal 40, line_spacing
    assert_in_delta 80.0, tall[1], 0.001, "max(40, cropHeight) + 1 * 40"
    assert_in_delta 2.5, spacing, 0.0001
    assert_in_delta base[0] + 2.5, spaced[0], 0.001, "one inter-character gap for two characters"
    assert_equal(-5, negative, "XNA stores a negative line spacing without complaint")
    # DEVIATION, recorded: XNA stores NaN too; `cna_sprite_font_set_spacing` documents "must be
    # finite" and refuses it, and that refusal is CNA's rather than a managed rule invented here.
    assert_equal CNA::NativeError, nan
    assert_equal TypeError, wrong_type
  end

  def test_null_text_is_refused_by_both_overloads
    values = with_font do |font|
      err = ->(&block) { begin; block.call; :ok; rescue => e; e.class; end }
      [err.call { font.MeasureString(nil) }, err.call { font.MeasureString(123) },
       err.call { font.MeasureString(:hello) }, err.call { font.MeasureString("ok") }]
    end
    assert_equal [ArgumentError, TypeError, TypeError, :ok], values
  end

  # ------------------------------------------------------------------- and exactly what it does not

  # DEVIATION, recorded: XNA's SpriteFont is not IDisposable — the ContentManager records the
  # Texture2D its reader built and disposes that. CNA hands back two owned handles and no projected
  # Texture2D, so the font owns both, and the manager disposes it because it records anything
  # answering `Dispose`.
  def test_unloading_the_manager_releases_the_font_and_its_atlas
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]
    directory = ENV["CNA_TEST_XNB_DIR"]
    skip "CNA_TEST_XNB_DIR not supplied" unless directory && File.file?(File.join(directory, "Default.xnb"))

    game = Host.new do |font|
      before = [font.IsDisposed, font.__send__(:texture_handle) != 0]
      # `SpriteFont` declares no `Dispose` of its own; it answers one only through the shared
      # native-resource module, which is what makes the manager record it.
      declared = G::SpriteFont.public_instance_methods(false)
      [before, declared.include?(:Dispose), font]
    end
    game.Run
    (before, declares_dispose, font) = game.result
    game.Dispose

    assert_equal [false, true], before, "loaded, with a real atlas handle beside it"
    assert_equal false, declares_dispose, "no Dispose identity of its own"
    assert_equal true, font.IsDisposed, "but the manager released it when the game went"
  end

  def test_it_adds_no_sprite_batch_draw_string_or_effect_surface
    # `DrawString` arrived in a later milestone -- the one this font's whole measurement surface
    # was built for. What **this** milestone claimed is that it added no drawing of its own, and
    # the SpriteBatch members it named are still what that type owes.
    assert G::SpriteBatch.public_method_defined?(:DrawString)
    remainder = ReviewedScoreboard.partial_remainder(STRICT, "Microsoft.Xna.Framework.Graphics.SpriteBatch")
                                  .map { |entry| entry.split("::", 2).last.sub(/ \(\d+ overloads?\)\z/, "") }
    assert_equal %w[Begin Draw], remainder.sort
    %i[Effect EffectParameter EffectAnnotation GraphicsAdapter].each do |absent|
      refute G.const_defined?(absent, false), absent.to_s
    end
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    assert_equal 7, symbols.count { |s| s.start_with?("cna_sprite_font_") }
    refute_includes symbols, "cna_sprite_font_create"
  end
end
