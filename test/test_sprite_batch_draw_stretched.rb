# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `SpriteBatch.Draw`'s three destination-rectangle overloads, which complete that member and leave
# `SpriteBatch` owing only the two `Begin` forms that need an `Effect`.
class SpriteBatchDrawStretchedTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.SpriteBatch"

  # ------------------------------------------------------------------- the contract, from metadata

  # Seven overloads split by the second parameter: four take a `Vector2` position and are scaled
  # from it, three take a `Rectangle` destination and are stretched into it. The stretched forms
  # carry no scale at all, which is why the longest of them has eight parameters where the position
  # form has nine.
  def test_the_seven_overloads_split_on_the_second_parameter
    overloads = REFERENCE.fetch(NAME).fetch("members")
                         .select { |member| member.fetch("name") == "Draw" }
                         .map { |member| member.fetch("parameters").map { |p| p.fetch("type") } }
    assert_equal 7, overloads.length
    positioned, stretched = overloads.partition { |types| types[1] == "Microsoft.Xna.Framework.Vector2" }
    assert_equal 4, positioned.length
    assert_equal 3, stretched.length
    assert_equal ["Microsoft.Xna.Framework.Rectangle"], stretched.map { |types| types[1] }.uniq
    assert_equal [3, 4, 8], stretched.map(&:length).sort
    assert_equal [3, 4, 9, 9], positioned.map(&:length).sort
    refute stretched.any? { |types| types.include?("System.Single") && types.length < 8 }
  end

  def test_draw_is_complete_and_only_the_effect_begin_overloads_are_left
    assert_equal ReviewedScoreboard::TARGET_MEMBERS, STRICT.fetch("TARGET_MEMBERS")
    assert_equal ReviewedScoreboard::MISSING_MEMBER, STRICT.fetch("MISSING_MEMBER")
    # Both of those needed an `Effect`, which the cluster built in the milestone after this one,
    # completing the type. What **this** milestone claimed -- that `Draw` was finished -- stands.
    assert_empty ReviewedScoreboard.partial_remainder(STRICT, NAME)
    assert_equal 7, REFERENCE.fetch(NAME).fetch("members").count { |member| member.fetch("name") == "Draw" }
  end

  def test_the_route_and_layout_are_cnas_own_split
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    assert_includes symbols, "cna_sprite_batch_submit_many"
    assert_includes symbols, "cna_sprite_batch_submit_scaled_many"
    layout = CNA::Native::Layouts::SpriteCommand
    assert_equal 72, layout.size
    assert_equal %w[struct_size struct_version texture destination source color rotation origin
                    effects layer_depth], layout.fields.map(&:name)
    # The scaled command carries a scale where this one carries a destination; that is the split.
    scaled = CNA::Native::Layouts::SpriteScaledCommand.fields.map(&:name)
    assert_includes scaled, "scale"
    refute_includes scaled, "destination"
    refute_includes layout.fields.map(&:name), "scale"
  end

  # ------------------------------------------------------------------------------ live behaviour

  class DrawGame < F::Game
    attr_reader :result

    def initialize(&body)
      @body = body
      @result = nil
      super()
      F::GraphicsDeviceManager.new(self)
    end

    def LoadContent
      texture = File.open(ENV.fetch("CNA_TEST_PNG"), "rb") do |stream|
        G::Texture2D.FromStream(self.GraphicsDevice, stream)
      end
      @result = @body.call(G::SpriteBatch.new(self.GraphicsDevice), texture)
    ensure
      self.Exit
    end
  end

  def with_batch
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]
    skip "CNA_TEST_PNG not supplied" unless ENV["CNA_TEST_PNG"] && File.file?(ENV["CNA_TEST_PNG"].to_s)

    game = DrawGame.new { |batch, texture| yield batch, texture }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  def test_all_three_stretched_shapes_submit
    values = with_batch do |batch, texture|
      destination = F::Rectangle.new(10, 20, 64, 48)
      source = F::Rectangle.new(0, 0, 32, 32)
      batch.Begin
      results = [
        batch.Draw(texture, destination, F::Color.White),
        batch.Draw(texture, destination, source, F::Color.White),
        batch.Draw(texture, destination, source, F::Color.White,
                   0.5, F::Vector2.Zero, G::SpriteEffects::FlipVertically, 0.25),
        # A null source is the whole texture, exactly as it is for the position overloads.
        batch.Draw(texture, destination, nil, F::Color.White)
      ]
      batch.End
      results
    end
    assert_equal [nil, nil, nil, nil], values
  end

  # The dispatch is on the second argument's runtime type, which is what the CLR's overload
  # resolution does statically. Both families still work in the same interval.
  def test_both_families_dispatch_in_the_same_interval
    values = with_batch do |batch, texture|
      batch.Begin
      results = [
        batch.Draw(texture, F::Vector2.new(1, 2), F::Color.White),
        batch.Draw(texture, F::Rectangle.new(0, 0, 8, 8), F::Color.White),
        batch.Draw(texture, F::Vector2.new(1, 2), nil, F::Color.White,
                   0.0, F::Vector2.Zero, 2.0, G::SpriteEffects::None, 0.0)
      ]
      batch.End
      results
    end
    assert_equal [nil, nil, nil], values
  end

  def test_the_arity_and_type_refusals
    values = with_batch do |batch, texture|
      destination = F::Rectangle.new(0, 0, 4, 4)
      batch.Begin
      results = [
        (begin; batch.Draw(texture, destination); nil; rescue => e; e.class; end),
        (begin; batch.Draw(texture, destination, F::Color.White, 1); nil; rescue => e; e.class; end),
        (begin; batch.Draw(texture, destination, 0); nil; rescue => e; e.class; end),
        (begin; batch.Draw(texture, destination, F::Vector2.Zero, F::Color.White); nil; rescue => e; e.class; end),
        (begin
           batch.Draw(texture, destination, nil, F::Color.White,
                      Float::NAN, F::Vector2.Zero, G::SpriteEffects::None, 0.0)
           nil
         rescue => e
           e.class
         end),
        (begin; batch.Draw("texture", destination, F::Color.White); nil; rescue => e; e.class; end)
      ]
      batch.End
      results
    end
    assert_equal [ArgumentError, TypeError, TypeError, TypeError, RangeError, TypeError], values
  end

  def test_it_requires_an_interval
    values = with_batch do |batch, texture|
      begin
        batch.Draw(texture, F::Rectangle.new(0, 0, 1, 1), F::Color.White)
        nil
      rescue => error
        error.class
      end
    end
    assert_equal CNA::InvalidBindingStateError, values
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_adds_no_effect_or_mesh_surface
    # `Effect` left this list when the cluster was built; what this milestone claimed, and still
    # claims, is that **it** built none of it.
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    refute_includes symbols, "cna_sprite_batch_draw_mesh_ext"
    refute_includes symbols, "cna_sprite_batch_begin_with_states"
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
  end
end
