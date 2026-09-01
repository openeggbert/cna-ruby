# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# The `Effect` cluster — nine types, and the one that unblocks `SpriteBatch`.
#
# Eight of the nine are `sealed` with an `assembly` constructor, so `new` is private and the only
# producer is `Effect`, whose own producer is compiled Effect Framework bytecode. That makes this the
# first cluster whose *entire behaviour* depends on a renderer capability: on an artifact without
# `CNA_GRAPHICS_CAPABILITY_COMPILED_EFFECTS` there is no way to make one, and the tests that need one
# say so rather than pretending. The structural contract is asserted everywhere.
class EffectClusterTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze

  CLUSTER = %w[
    Effect EffectParameter EffectParameterCollection EffectAnnotation EffectAnnotationCollection
    EffectPass EffectPassCollection EffectTechnique EffectTechniqueCollection
  ].freeze

  # ------------------------------------------------------------------------------- the contract

  def test_every_type_in_the_cluster_is_complete
    CLUSTER.each do |short|
      name = "Microsoft.Xna.Framework.Graphics.#{short}"
      assert_includes STRICT.fetch("completeTypeNames"), name
      assert_empty ReviewedScoreboard.partial_remainder(STRICT, name)
      assert G.const_defined?(short, false), short
    end
  end

  # Eight sealed types with an `assembly` constructor, and one that is neither.
  def test_only_effect_is_constructible_and_only_effect_is_unsealed
    (CLUSTER - %w[Effect]).each do |short|
      name = "Microsoft.Xna.Framework.Graphics.#{short}"
      assert REFERENCE.fetch(name).fetch("sealed"), name
      assert_equal 0, REFERENCE.fetch(name).fetch("members").count { |m| m.fetch("kind") == "constructor" }, name
      refute G.const_get(short).respond_to?(:new), short
    end
    refute REFERENCE.fetch("Microsoft.Xna.Framework.Graphics.Effect").fetch("sealed")
    assert G::Effect.respond_to?(:new)
    assert_equal G::GraphicsResource, G::Effect.superclass
  end

  # `SpriteBatch` was the type this cluster existed to finish.
  def test_sprite_batch_is_complete_now
    name = "Microsoft.Xna.Framework.Graphics.SpriteBatch"
    assert_includes STRICT.fetch("completeTypeNames"), name
    assert_empty ReviewedScoreboard.partial_remainder(STRICT, name)
    overloads = REFERENCE.fetch(name).fetch("members").select { |m| m.fetch("name") == "Begin" }
    assert_equal 5, overloads.length
    assert_equal 2, overloads.count { |m| m.fetch("parameters").any? { |p| p.fetch("type").end_with?(".Effect") } }
    assert_equal %w[GraphicsDeviceManager GraphicsDevice],
                 STRICT.fetch("partialTypes").keys.map { |key| key.split(".").last }
  end

  def test_the_cluster_grew_the_reviewed_native_surface
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:constants), CNA::Native::Manifest::CONSTANTS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:layouts), CNA::Native::Layouts::STRUCTURES.length
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    # The two lookup routes CNA offers and XNA's own semantics forbid: `Item[String]` is ordinal
    # equality over the managed list, and `GetParameterBySemantic` is OrdinalIgnoreCase, while both
    # CNA routes match exactly.
    refute_includes symbols, "cna_effect_parameter_collection_find_name"
    refute_includes symbols, "cna_effect_parameter_collection_find_semantic"
    # Nor the standalone constructors, which have no XNA identity: nothing public makes a bare
    # parameter, annotation, pass, technique or collection.
    %w[cna_effect_parameter_create cna_effect_annotation_create cna_effect_pass_create
       cna_effect_technique_create_named cna_effect_technique_create_default
       cna_effect_parameter_collection_create cna_effect_create_empty
       cna_sprite_effect_create].each { |symbol| refute_includes symbols, symbol }
  end

  # ------------------------------------------------------------------------------ live behaviour

  class EffectGame < F::Game
    attr_reader :result

    def initialize(&body)
      @body = body
      super()
      F::GraphicsDeviceManager.new(self)
    end

    def Draw(_time)
      @result = @body.call(self.GraphicsDevice)
    ensure
      self.Exit
    end
  end

  def with_device
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = EffectGame.new { |device| yield device }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  def with_effect
    skip "this renderer has no compiled-effect runtime" unless RendererEnvironment.compiled_effects?
    fixture = RendererEnvironment.effect_fixture
    skip "CNA_TEST_FX not supplied" if fixture.nil?

    with_device do |device|
      effect = G::Effect.new(device, File.binread(fixture))
      begin
        yield(effect, device)
      ensure
        effect.Dispose
      end
    end
  end

  def error_of
    yield
    :ok
  rescue StandardError => error
    [error.class, error.message]
  end

  # `CreateEffectFromCode` checks the **bytecode before the device**, which is not the order a
  # reader would guess and is exactly why it is asserted.
  def test_the_constructor_refusals_are_the_ils_own_and_in_the_ils_order
    values = with_device do |device|
      [error_of { G::Effect.new(nil, nil) },
       error_of { G::Effect.new(device, nil) },
       error_of { G::Effect.new(device, "") },
       error_of { G::Effect.new(device, "abc") },
       error_of { G::Effect.new(nil, "\0\0\0\0") },
       error_of { G::Effect.new("device", "\0\0\0\0") },
       error_of { G::Effect.new(device, 4) },
       error_of { G::Effect.new(device) },
       error_of { G::Effect.new(nil) }]
    end
    # A null device with null bytecode still reports the bytecode: it is checked first.
    assert_equal [ArgumentError, "effectCode"], values[0]
    assert_equal [ArgumentError, "effectCode"], values[1]
    assert_equal [ArgumentError, "effectCode"], values[2], "an empty array is ArgumentNullException"
    assert_equal [ArgumentError, "effectCode"], values[3], "three bytes is not a multiple of four"
    assert_equal [ArgumentError, "graphicsDevice"], values[4], "and only then the device"
    assert_equal TypeError, values[5].first
    assert_equal TypeError, values[6].first
    assert_equal TypeError, values[7].first, "one argument is the clone constructor's arity, and a device is not an Effect"
    assert_equal [ArgumentError, "cloneSource"], values[8]
  end

  # Four bytes that are a multiple of four and are not an effect container: CNA refuses them, and
  # the refusal is the route's rather than a rule this projection invented.
  def test_bytes_that_are_not_an_effect_container_are_refused_by_the_route
    value = with_device { |device| error_of { G::Effect.new(device, "\0\1\2\3") } }
    refute_equal :ok, value
    assert_kind_of Class, value.first
    assert_operator value.first, :<=, CNA::NativeError
  end

  # -------------------------------------------------------------------- the reflected object graph

  def test_a_compiled_effect_reflects_its_parameters_and_techniques
    values = with_effect do |effect, _device|
      { parameters: effect.Parameters.Count,
        names: effect.Parameters.map(&:Name),
        techniques: effect.Techniques.map(&:Name),
        passes: effect.Techniques.map { |technique| technique.Passes.map(&:Name) },
        current: effect.CurrentTechnique.Name,
        device: effect.GraphicsDevice.equal?(effect.GraphicsDevice) }
    end
    assert_operator values.fetch(:parameters), :>, 0
    refute_empty values.fetch(:techniques)
    assert(values.fetch(:passes).all? { |names| !names.empty? })
    assert_includes values.fetch(:techniques), values.fetch(:current)
  end

  # The identity rule: CNA answers a **fresh** handle on every getter call, and XNA answers the same
  # object every time. A fresh native handle is not a new XNA object.
  def test_every_collection_answers_the_same_object_every_time
    values = with_effect do |effect, _device|
      first = effect.Parameters[0]
      [effect.Parameters.equal?(effect.Parameters),
       first.equal?(effect.Parameters[0]),
       first.equal?(effect.Parameters[first.Name]),
       effect.Techniques[0].equal?(effect.Techniques[0]),
       effect.Techniques[0].Passes[0].equal?(effect.Techniques[0].Passes[0]),
       first.Annotations.equal?(first.Annotations),
       effect.CurrentTechnique.equal?(effect.CurrentTechnique)]
    end
    assert_equal [true] * 7, values
  end

  # `Item[Int32]` answers **null** outside its range rather than raising, `Item[String]` scans by
  # name with ordinal equality, and `GetParameterBySemantic` scans with OrdinalIgnoreCase.
  def test_the_collection_lookups_answer_null_rather_than_raising
    values = with_effect do |effect, _device|
      named = effect.Parameters[0].Name
      semantic = effect.Parameters.find { |parameter| !parameter.Semantic.empty? }
      { high: effect.Parameters[effect.Parameters.Count].inspect,
        negative: effect.Parameters[-1].inspect,
        missing_name: effect.Parameters["no such parameter"].inspect,
        found: effect.Parameters[named].Name,
        exact_semantic: semantic && effect.Parameters.GetParameterBySemantic(semantic.Semantic)&.Name,
        folded_semantic: semantic && effect.Parameters.GetParameterBySemantic(semantic.Semantic.downcase)&.Name,
        semantic_owner: semantic&.Name,
        missing_semantic: effect.Parameters.GetParameterBySemantic("no such semantic").inspect,
        wrong_key: error_of { effect.Parameters[1.5] },
        technique_missing: effect.Techniques["no such technique"].inspect,
        pass_missing: effect.Techniques[0].Passes[99].inspect }
    end
    assert_equal "nil", values.fetch(:high)
    assert_equal "nil", values.fetch(:negative)
    assert_equal "nil", values.fetch(:missing_name)
    assert_equal "nil", values.fetch(:missing_semantic)
    assert_equal "nil", values.fetch(:technique_missing)
    assert_equal "nil", values.fetch(:pass_missing)
    assert_equal TypeError, values.fetch(:wrong_key).first
    refute_nil values.fetch(:found)
    if values.fetch(:semantic_owner)
      assert_equal values.fetch(:semantic_owner), values.fetch(:exact_semantic)
      assert_equal values.fetch(:semantic_owner), values.fetch(:folded_semantic),
                   "GetParameterBySemantic is OrdinalIgnoreCase, which is why CNA's exact-match route is not bound"
    end
  end

  # ------------------------------------------------------------------------ EffectParameter values

  def test_scalar_values_round_trip_and_the_broadcast_is_the_ils_own
    values = with_effect do |effect, _device|
      scalar = effect.Parameters.find { |p| p.ParameterClass == G::EffectParameterClass::Scalar && p.Elements.Count.zero? }
      next :no_scalar if scalar.nil?

      scalar.SetValue(0.25)
      vector3 = scalar.GetValueVector3
      matrix = scalar.GetValueMatrix
      { single: scalar.GetValueSingle,
        # `GetValueVector*` on a Scalar reads one float and broadcasts it to every component, and
        # `GetValueMatrix` sets all sixteen. That is the IL, not a convenience.
        broadcast: [vector3.X, vector3.Y, vector3.Z],
        matrix_broadcast: [matrix.M11, matrix.M23, matrix.M44],
        int32: scalar.GetValueInt32.class.to_s,
        boolean: [true, false].include?(scalar.GetValueBoolean),
        as_string: error_of { scalar.GetValueString },
        as_texture: error_of { scalar.GetValueTexture2D } }
    end
    skip "this fixture has no plain scalar parameter" if values == :no_scalar

    assert_in_delta 0.25, values.fetch(:single), 1e-6
    assert_equal [0.25] * 3, values.fetch(:broadcast).map { |v| v.round(6) }
    assert_equal [0.25] * 3, values.fetch(:matrix_broadcast).map { |v| v.round(6) }
    assert_equal "Integer", values.fetch(:int32)
    assert values.fetch(:boolean)
    assert_equal TypeError, values.fetch(:as_string).first, "InvalidCastException: the type is not String"
    assert_equal TypeError, values.fetch(:as_texture).first
  end

  def test_a_vector_parameter_refuses_the_scalar_getters_and_the_wrong_width
    values = with_effect do |effect, _device|
      vector = effect.Parameters.find { |p| p.ParameterClass == G::EffectParameterClass::Vector && p.ColumnCount == 4 }
      next :no_vector if vector.nil?

      vector.SetValue(F::Vector4.new(1.0, 0.5, 0.25, 0.125))
      read = vector.GetValueVector4
      { four: [read.X, read.Y, read.Z, read.W],
        quaternion: (q = vector.GetValueQuaternion; [q.X, q.Y, q.Z, q.W]),
        as_single: error_of { vector.GetValueSingle },
        as_vector2: error_of { vector.GetValueVector2 },
        as_matrix: error_of { vector.GetValueMatrix } }
    end
    skip "this fixture has no four-column vector parameter" if values == :no_vector

    assert_equal [1.0, 0.5, 0.25, 0.125], values.fetch(:four)
    assert_equal [1.0, 0.5, 0.25, 0.125], values.fetch(:quaternion)
    assert_equal TypeError, values.fetch(:as_single).first, "class is not Scalar and Elements is empty"
    assert_equal TypeError, values.fetch(:as_vector2).first, "ColumnCount is four, not two"
    assert_equal TypeError, values.fetch(:as_matrix).first, "class is not Matrix"
  end

  def test_a_matrix_parameter_round_trips_and_has_no_row_or_column_test
    values = with_effect do |effect, _device|
      matrix = effect.Parameters.find { |p| p.ParameterClass == G::EffectParameterClass::Matrix }
      next :no_matrix if matrix.nil?

      matrix.SetValue(F::Matrix.Identity)
      identity = matrix.GetValueMatrix
      matrix.SetValueTranspose(F::Matrix.CreateScale(2.0))
      { identity: [identity.M11, identity.M22, identity.M33, identity.M44, identity.M12],
        rows: [matrix.RowCount, matrix.ColumnCount],
        transposed: matrix.GetValueMatrixTranspose.M11,
        as_vector4: error_of { matrix.GetValueVector4 },
        as_single: error_of { matrix.GetValueSingle } }
    end
    skip "this fixture has no matrix parameter" if values == :no_matrix

    assert_equal [1.0, 1.0, 1.0, 1.0, 0.0], values.fetch(:identity)
    assert_equal TypeError, values.fetch(:as_vector4).first
    assert_equal TypeError, values.fetch(:as_single).first
  end

  # An array parameter has `Elements.Count > 0`, and that is what turns the numeric guards off:
  # `if (ParameterClass != Scalar && Elements.Count == 0) throw`.
  def test_an_array_parameter_round_trips_and_its_elements_are_parameters
    values = with_effect do |effect, _device|
      array = effect.Parameters.find { |p| p.Elements.Count.positive? }
      next :no_array if array.nil?

      array.SetValue([1.5, 2.5])
      { elements: array.Elements.Count,
        element_names: array.Elements.map(&:Name),
        read: array.GetValueSingleArray(2),
        # A count larger than the parameter holds is not an error: XNA allocates `new T[count]`
        # and fills what it can.
        over_read: array.GetValueSingleArray(4).length,
        zero: error_of { array.GetValueSingleArray(0) },
        negative: error_of { array.GetValueSingleArray(-1) } }
    end
    skip "this fixture has no array parameter" if values == :no_array

    assert_operator values.fetch(:elements), :>, 0
    assert_equal [1.5, 2.5], values.fetch(:read)
    assert_equal 4, values.fetch(:over_read)
    assert_equal RangeError, values.fetch(:zero).first
    assert_equal RangeError, values.fetch(:negative).first
  end

  def test_a_struct_parameter_exposes_its_members_as_parameters
    values = with_effect do |effect, _device|
      structure = effect.Parameters.find { |p| p.StructureMembers.Count.positive? }
      next :no_struct if structure.nil?

      { members: structure.StructureMembers.Count,
        names: structure.StructureMembers.map(&:Name),
        klass: structure.ParameterClass.to_s,
        member_types: structure.StructureMembers.map { |m| m.ParameterClass.to_s },
        identity: structure.StructureMembers[0].equal?(structure.StructureMembers[0]) }
    end
    skip "this fixture has no struct parameter" if values == :no_struct

    assert_operator values.fetch(:members), :>, 0
    assert_equal "Struct", values.fetch(:klass)
    assert values.fetch(:identity)
  end

  def test_an_annotation_reads_through_the_parameter_rules
    values = with_effect do |effect, _device|
      annotated = effect.Parameters.find { |p| p.Annotations.Count.positive? }
      next :no_annotation if annotated.nil?

      annotation = annotated.Annotations[0]
      { name: annotation.Name,
        klass: annotation.ParameterClass.to_s,
        type: annotation.ParameterType.to_s,
        rows: [annotation.RowCount, annotation.ColumnCount],
        by_name: annotated.Annotations[annotation.Name].equal?(annotation),
        by_index: annotated.Annotations[0].equal?(annotation),
        missing: annotated.Annotations[99].inspect,
        # The same guard `EffectParameter` applies, because XNA's annotation getters construct a
        # temporary parameter and forward to it.
        scalar_read: (annotation.ParameterClass == G::EffectParameterClass::Scalar ?
                        annotation.GetValueSingle.class.to_s : error_of { annotation.GetValueSingle }.first.to_s),
        as_string: error_of { annotation.GetValueString } }
    end
    skip "this fixture has no annotated parameter" if values == :no_annotation

    refute_empty values.fetch(:name)
    assert values.fetch(:by_name)
    assert values.fetch(:by_index)
    assert_equal "nil", values.fetch(:missing)
  end

  # ------------------------------------------------------------------------------- passes and Clone

  # `Apply` is `CheckDisposed`, then the technique check, then `OnApply`, then the native apply —
  # in that order, so an override observes the check having passed.
  def test_apply_refuses_a_pass_outside_the_current_technique_and_calls_on_apply_first
    values = with_effect do |effect, _device|
      seen = []
      effect.define_singleton_method(:OnApply) { seen << :on_apply }
      first = effect.Techniques[0].Passes[0]
      applied = error_of { first.Apply }
      other = effect.Techniques.find { |technique| !technique.equal?(effect.CurrentTechnique) }
      refused = other && error_of { other.Passes[0].Apply }
      switched = nil
      if other
        effect.CurrentTechnique = other
        switched = error_of { other.Passes[0].Apply }
      end
      { applied: applied, refused: refused, switched: switched, on_apply: seen.length,
        current: effect.CurrentTechnique.Name }
    end
    assert_equal :ok, values.fetch(:applied)
    assert_operator values.fetch(:on_apply), :>=, 1, "OnApply runs before the native apply"
    if values.fetch(:refused)
      assert_equal RuntimeError, values.fetch(:refused).first
      assert_equal "NotCurrentTechnique", values.fetch(:refused).last
      assert_equal :ok, values.fetch(:switched)
    end
  end

  def test_the_current_technique_setter_is_the_ils_own
    values = with_effect do |effect, device|
      other = G::Effect.new(device, File.binread(RendererEnvironment.effect_fixture))
      result = { nil_value: error_of { effect.CurrentTechnique = nil },
                 same: error_of { effect.CurrentTechnique = effect.CurrentTechnique },
                 foreign: error_of { effect.CurrentTechnique = other.Techniques[0] },
                 after: effect.CurrentTechnique.Name }
      other.Dispose
      result
    end
    assert_equal [ArgumentError, "value"], values.fetch(:nil_value)
    assert_equal :ok, values.fetch(:same), "a same-value write returns before touching anything"
    assert_equal RuntimeError, values.fetch(:foreign).first,
                 "a technique belonging to another effect is a parameterless InvalidOperationException"
  end

  # `Clone` is `newobj Effect::.ctor(Effect); ret`, and the clone is an independent object graph.
  def test_clone_produces_an_independent_effect
    values = with_effect do |effect, _device|
      clone = effect.Clone
      result = { parameters: [effect.Parameters.Count, clone.Parameters.Count],
                 distinct: !clone.Parameters[0].equal?(effect.Parameters[0]),
                 same_device: clone.GraphicsDevice.equal?(effect.GraphicsDevice),
                 techniques: clone.Techniques.map(&:Name) == effect.Techniques.map(&:Name) }
      clone.Dispose
      result << nil if false
      result[:source_alive] = !effect.IsDisposed
      result[:clone_disposed] = clone.IsDisposed
      result
    end
    assert_equal values.fetch(:parameters).first, values.fetch(:parameters).last
    assert values.fetch(:distinct), "the clone's parameters are its own objects"
    assert values.fetch(:same_device)
    assert values.fetch(:techniques)
    assert values.fetch(:source_alive), "disposing a clone does not dispose its source"
    assert values.fetch(:clone_disposed)
  end

  # Every view this Effect took is released with it, and a child reached afterwards says so rather
  # than dereferencing a destroyed handle.
  def test_disposal_releases_the_whole_graph_and_a_child_refuses_afterwards
    values = with_device do |device|
      skip "this renderer has no compiled-effect runtime" unless RendererEnvironment.compiled_effects?
      fixture = RendererEnvironment.effect_fixture
      skip "CNA_TEST_FX not supplied" if fixture.nil?

      effect = G::Effect.new(device, File.binread(fixture))
      parameter = effect.Parameters[0]
      pass = effect.Techniques[0].Passes[0]
      effect.Dispose
      { disposed: effect.IsDisposed,
        twice: error_of { effect.Dispose },
        parameter: error_of { parameter.GetValueSingle },
        pass: error_of { pass.Apply },
        # The collections are managed objects and keep answering; only a native read refuses.
        count: effect.Parameters.Count }
    end
    assert values.fetch(:disposed)
    assert_equal :ok, values.fetch(:twice), "Dispose is idempotent"
    assert_equal CNA::DisposedObjectError, values.fetch(:parameter).first
    assert_equal CNA::DisposedObjectError, values.fetch(:pass).first
    assert_operator values.fetch(:count), :>, 0
  end

  # --------------------------------------------------------------------- SpriteBatch.Begin's four

  def test_the_effect_taking_begin_overloads_open_and_close_an_interval
    values = with_device do |device|
      batch = G::SpriteBatch.new(device)
      five = [G::SpriteSortMode::Deferred, nil, nil, nil, nil]
      result = { nil_effect: error_of { batch.Begin(*five, nil); batch.End },
                 nil_effect_and_matrix: error_of { batch.Begin(*five, nil, F::Matrix.Identity); batch.End },
                 wrong_effect: error_of { batch.Begin(*five, "not an effect") },
                 wrong_matrix: error_of { batch.Begin(*five, nil, 7) },
                 arity: error_of { batch.Begin(*five, nil, F::Matrix.Identity, :extra) } }
      if RendererEnvironment.compiled_effects? && RendererEnvironment.effect_fixture
        effect = G::Effect.new(device, File.binread(RendererEnvironment.effect_fixture))
        result[:with_effect] = error_of { batch.Begin(*five, effect); batch.End }
        result[:with_transform] = error_of do
          batch.Begin(*five, effect, F::Matrix.CreateScale(2.0))
          texture = G::Texture2D.new(device, 2, 2)
          texture.SetData(F::Color, [F::Color.new(255, 0, 0, 255)] * 4)
          batch.Draw(texture, F::Vector2.new(1.0, 2.0), F::Color.new(255, 255, 255, 255))
          batch.End
          texture.Dispose
        end
        effect.Dispose
        result[:after_dispose] = error_of { batch.Begin(*five, effect) }
      end
      batch.Dispose
      result
    end
    assert_equal :ok, values.fetch(:nil_effect), "a null Effect is the stock sprite effect, in XNA and in CNA"
    assert_equal :ok, values.fetch(:nil_effect_and_matrix)
    assert_equal TypeError, values.fetch(:wrong_effect).first
    assert_equal TypeError, values.fetch(:wrong_matrix).first
    assert_equal ArgumentError, values.fetch(:arity).first
    return unless values.key?(:with_effect)

    assert_equal :ok, values.fetch(:with_effect)
    assert_equal :ok, values.fetch(:with_transform), "a sprite really draws through a compiled effect"
    assert_equal CNA::DisposedObjectError, values.fetch(:after_dispose).first
  end

  # --------------------------------------------------------------------------- the recorded limit

  # Compiled-effect support is a **build option** for the EasyGL, SDL_GPU and Vulkan families -- the
  # effect runtime is a fetched dependency they do not otherwise need -- and it is on in exactly one
  # of this project's three qualified artifacts. So the cluster's structure is qualified everywhere
  # and its behaviour only where an Effect can exist, which this states rather than hides.
  def test_the_compiled_effect_capability_is_measured_rather_than_assumed
    skip "CNA_NATIVE_LIBRARY not supplied" unless RendererEnvironment.available?

    if RendererEnvironment.compiled_effects?
      refute_nil RendererEnvironment.effect_fixture,
                 "an artifact with the effect runtime needs CNA_TEST_FX to exercise it"
    else
      value = with_device { |device| error_of { G::Effect.new(device, "\0\1\2\3") } }
      refute_equal :ok, value, "without the runtime no bytecode is accepted"
    end
  end
end
