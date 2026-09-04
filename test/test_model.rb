# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "open3"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# The Model family: eight types, one object graph, and two upstream crashes it has to live beside.
#
# ## Why the measured half runs in a child process
#
# Loading a model makes **process shutdown** segfault — measured on all three qualified artifacts,
# with the game already disposed, with nothing of the graph touched, and with no Ruby in the path.
# `docs/model-load-shutdown-upstream-defect.md` carries the whole reproduction. So every test here
# that loads a real model runs in a child that ends with `exit!`, which skips the shutdown path the
# fault lives in, and `test_loading_a_model_still_crashes_at_shutdown` asserts the fault itself: the
# same child *without* `exit!` must die on a signal. When a later CNA fixes it, that test fails and
# the child process comes out.
class ModelTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FAMILY = %w[Model ModelBone ModelMesh ModelMeshPart
              ModelBoneCollection ModelMeshCollection ModelMeshPartCollection
              ModelEffectCollection].freeze
  ASSET = "BlenderDefaultCube"

  def fixture_dir = ENV["CNA_TEST_XNB_DIR"]

  def native? = !ENV["CNA_NATIVE_LIBRARY"].to_s.empty?

  # ------------------------------------------------------------------ the surface

  def test_all_eight_and_their_four_enumerators_are_complete
    FAMILY.each do |name|
      assert ReviewedScoreboard.complete?(STRICT, "Microsoft.Xna.Framework.Graphics.#{name}"), name
    end
    %w[ModelBoneCollection ModelMeshCollection ModelMeshPartCollection ModelEffectCollection].each do |name|
      assert ReviewedScoreboard.complete?(STRICT, "Microsoft.Xna.Framework.Graphics.#{name}+Enumerator"), name
    end
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
  end

  # Every one of the eight has an `assembly` constructor: `ContentManager.Load` is the only way in.
  def test_none_of_them_can_be_constructed
    FAMILY.each do |name|
      klass = G.const_get(name)
      refute klass.singleton_class.public_method_defined?(:new), name
      assert_raises(NoMethodError) { klass.new }
    end
  end

  # The four collections really inherit the BCL projection rather than flattening it, and each
  # declares the CLR element type its base is closed over.
  def test_the_four_collections_are_read_only_collections_of_their_element
    {
      "ModelBoneCollection" => "Microsoft.Xna.Framework.Graphics.ModelBone",
      "ModelMeshCollection" => "Microsoft.Xna.Framework.Graphics.ModelMesh",
      "ModelMeshPartCollection" => "Microsoft.Xna.Framework.Graphics.ModelMeshPart",
      "ModelEffectCollection" => "Microsoft.Xna.Framework.Graphics.Effect"
    }.each do |name, element|
      klass = G.const_get(name)
      assert_operator klass, :<, CNA::Runtime::ReadOnlyCollection, name
      assert_equal [element], klass.clr_element_types, name
      assert klass.const_defined?(:Enumerator, false), "#{name} must declare its nested Enumerator"
    end
  end

  # `Item[string]` and `TryGetValue` exist on the two named collections and on neither of the other
  # two, which is what the metadata says.
  def test_only_the_bone_and_mesh_collections_are_addressable_by_name
    %w[ModelBoneCollection ModelMeshCollection].each do |name|
      assert G.const_get(name).public_method_defined?(:TryGetValue), name
    end
    %w[ModelMeshPartCollection ModelEffectCollection].each do |name|
      refute G.const_get(name).public_method_defined?(:TryGetValue), name
    end
  end

  # `ModelEffectCollection.Add` and `.Remove` are `assembly` — `ModelMeshPart.set_Effect` is their
  # only caller — so neither is a public identity here.
  def test_the_effect_collections_mutators_are_not_public
    refute G::ModelEffectCollection.public_method_defined?(:Add)
    refute G::ModelEffectCollection.public_method_defined?(:Remove)
    assert G::ModelEffectCollection.private_method_defined?(:add_effect)
    assert G::ModelEffectCollection.private_method_defined?(:remove_effect)
  end

  # Six of `ModelMeshPart`'s eight properties are read-only; `Effect` and `Tag` are the two a
  # consumer may write.
  def test_the_mesh_parts_writable_members_are_the_ils_two
    writable = %i[StartIndex PrimitiveCount VertexOffset NumVertices IndexBuffer VertexBuffer
                  Effect Tag].select { |name| G::ModelMeshPart.public_method_defined?(:"#{name}=") }
    assert_equal %i[Effect Tag], writable
  end

  def test_the_bones_only_writable_member_is_its_transform
    writable = %i[Name Index Transform Parent Children]
               .select { |name| G::ModelBone.public_method_defined?(:"#{name}=") }
    assert_equal %i[Transform], writable
  end

  # `cna_model_destroy` is deliberately absent from the manifest: XNA's `Model` is not
  # `IDisposable`, so nothing wants it, and calling it on a content-loaded model segfaults.
  def test_the_model_declares_no_disposal_and_the_destroy_route_is_unbound
    FAMILY.each { |name| refute G.const_get(name).method_defined?(:Dispose), name }
    refute_includes CNA::Native::Manifest::FUNCTIONS.map(&:symbol), "cna_model_destroy"
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
  end

  # `ContentManager.Load` is the producer, and the registry is what `Load` dispatches on.
  def test_the_content_manager_is_the_only_producer
    assert_includes F::Content::ContentManager.supported_types, G::Model
  end

  # ------------------------------------------------------------------ the child process

  CHILD_PREAMBLE = <<~'CHILD'
    require "cna"
    require "json"
    F = Microsoft::Xna::Framework
    G = Microsoft::Xna::Framework::Graphics

    class ModelProbeGame < F::Game
      attr_reader :result

      def initialize(&body)
        @body = body
        super()
        F::GraphicsDeviceManager.new(self)
        self.Content.RootDirectory = ENV.fetch("CNA_TEST_XNB_DIR")
      end

      def Draw(_time)
        @result = @body.call(self)
      ensure
        self.Exit
      end
    end

    def in_a_game
      game = ModelProbeGame.new { |host| yield host }
      game.Run
      game.result
    ensure
      game&.Dispose
    end
  CHILD

  # Runs `body` in a child. `hard_exit: false` leaves the crashing shutdown path in, which is what
  # the upstream-defect test needs.
  def child(body, hard_exit: true)
    script = +CHILD_PREAMBLE
    script << body
    script << "\n$stdout.flush\nexit!(0)\n" if hard_exit
    output, status = Open3.capture2e({ "CNA_TEST_XNB_DIR" => fixture_dir },
                                     "ruby", "-I#{ROOT.join("lib")}", "-e", script, chdir: ROOT.to_s)
    [output, status]
  end

  def measured(body)
    output, status = child(body)
    assert status.success?, "child failed:\n#{output}"
    JSON.parse(output[/^\{.*\}$/m] || "{}")
  end

  def skip_unless_fixture
    skip "CNA_NATIVE_LIBRARY not supplied" unless native?
    skip "CNA_TEST_XNB_DIR not supplied" if fixture_dir.to_s.empty?
    skip "the model fixture is not on this host" unless File.exist?(File.join(fixture_dir, "#{ASSET}.xnb"))
  end

  # ------------------------------------------------------------------ the upstream crash

  # The defect itself, asserted from the outside. The child does exactly one thing — load a model —
  # and is allowed to shut down normally. It must die on a signal.
  def test_loading_a_model_still_crashes_at_shutdown
    skip_unless_fixture

    _output, status = child(<<~'BODY', hard_exit: false)
      in_a_game { |host| host.Content.Load(G::Model, "BlenderDefaultCube") && nil }
      puts "{}"
    BODY
    refute status.success?, "the shutdown crash is fixed upstream — remove the child-process " \
                            "workaround in test/test_model.rb and in the evidence document"
    assert status.signaled?, "expected a signal, got #{status.inspect}"
    assert_equal Signal.list.fetch("SEGV"), status.termsig
  end

  # And the same child *with* `exit!` is clean, which is what makes every test below possible.
  def test_the_same_child_is_clean_when_it_skips_the_shutdown_path
    skip_unless_fixture

    output, status = child(<<~'BODY')
      in_a_game { |host| host.Content.Load(G::Model, "BlenderDefaultCube") && nil }
      puts "{}"
    BODY
    assert status.success?, output
  end

  # ------------------------------------------------------------------ the graph

  # Everything the fixture's own manifest documents, read back through the projection: two bones
  # `RootNode` -> `Cube`, one mesh `Cube` whose bounding sphere is a unit cube's half-diagonal, one
  # part of 24 vertices and 12 primitives, one effect, one vertex buffer and one index buffer.
  def test_the_whole_graph_matches_the_fixtures_own_manifest
    skip_unless_fixture

    result = measured(<<~'BODY')
      out = in_a_game do |host|
        model = host.Content.Load(G::Model, "BlenderDefaultCube")
        mesh = model.Meshes[0]
        part = mesh.MeshParts[0]
        {
          bones: model.Bones.Count,
          bone_names: model.Bones.map(&:Name),
          bone_indices: model.Bones.map(&:Index),
          root: model.Root.Name,
          parents: model.Bones.map { |bone| bone.Parent&.Name },
          children: model.Bones.map { |bone| bone.Children.map(&:Name) },
          meshes: model.Meshes.Count,
          mesh_name: mesh.Name,
          parent_bone: mesh.ParentBone.Name,
          radius: mesh.BoundingSphere.Radius,
          parts: mesh.MeshParts.Count,
          part: [part.StartIndex, part.PrimitiveCount, part.VertexOffset, part.NumVertices],
          effects: mesh.Effects.Count,
          vertices: part.VertexBuffer.VertexCount,
          indices: part.IndexBuffer.IndexCount,
          tag: model.Tag.nil?
        }
      end
      puts JSON.generate(out)
    BODY
    assert_equal 2, result.fetch("bones")
    assert_equal %w[RootNode Cube], result.fetch("bone_names")
    assert_equal [0, 1], result.fetch("bone_indices")
    assert_equal "RootNode", result.fetch("root")
    assert_equal [nil, "RootNode"], result.fetch("parents")
    assert_equal [["Cube"], []], result.fetch("children")
    assert_equal 1, result.fetch("meshes")
    assert_equal "Cube", result.fetch("mesh_name")
    assert_equal "Cube", result.fetch("parent_bone")
    # A unit cube's half-diagonal is sqrt(3); the fixture's manifest says so and CNA answers it.
    assert_in_delta Math.sqrt(3), result.fetch("radius"), 1e-6
    assert_equal 1, result.fetch("parts")
    assert_equal [0, 12, 0, 24], result.fetch("part")
    assert_equal 1, result.fetch("effects")
    assert_equal 24, result.fetch("vertices")
    assert_equal 36, result.fetch("indices")
    assert result.fetch("tag"), "the fixture carries no Tag and none is fabricated"
  end

  # The property the whole graph is built for. CNA answers a **fresh handle on every call** for a
  # bone, mesh, part or collection view, so identity has to come from the projection: XNA's
  # `Bones[0]` is one object, and so is this one.
  def test_object_identity_is_preserved_everywhere_xna_preserves_it
    skip_unless_fixture

    result = measured(<<~'BODY')
      out = in_a_game do |host|
        model = host.Content.Load(G::Model, "BlenderDefaultCube")
        again = host.Content.Load(G::Model, "BlenderDefaultCube")
        mesh = model.Meshes[0]
        part = mesh.MeshParts[0]
        {
          model: model.equal?(again),
          bone: model.Bones[0].equal?(model.Bones[0]),
          root: model.Root.equal?(model.Bones[0]),
          parent: model.Bones[1].Parent.equal?(model.Bones[0]),
          child: model.Bones[0].Children[0].equal?(model.Bones[1]),
          parent_bone: mesh.ParentBone.equal?(model.Bones[1]),
          mesh: model.Meshes["Cube"].equal?(mesh),
          part: mesh.MeshParts[0].equal?(part),
          effect: mesh.Effects[0].equal?(part.Effect),
          buffers: [part.VertexBuffer.equal?(part.VertexBuffer),
                    part.IndexBuffer.equal?(part.IndexBuffer)]
        }
      end
      puts JSON.generate(out)
    BODY
    result.each do |key, value|
      next assert(value.all?, key) if value.is_a?(Array)

      assert value, key
    end
  end

  # `TryGetValue` is a linear scan comparing `Name` with `StringComparison.Ordinal` — `ldc.i4.4`,
  # so case-sensitive — and `Item[string]` is that with `KeyNotFoundException` on failure. A null or
  # empty name is `ArgumentNullException`.
  def test_lookup_by_name_is_ordinal_and_refuses_an_empty_name
    skip_unless_fixture

    result = measured(<<~'BODY')
      def error_of
        yield
        "ok"
      rescue StandardError => e
        e.class.name
      end

      out = in_a_game do |host|
        model = host.Content.Load(G::Model, "BlenderDefaultCube")
        {
          found: model.Bones.TryGetValue("Cube"),
          wrong_case: model.Bones.TryGetValue("cube"),
          absent: model.Bones.TryGetValue("nope"),
          yielded: (model.Bones.TryGetValue("Cube") { |bone| break bone.Index }),
          item: model.Bones["Cube"].Index,
          item_missing: error_of { model.Bones["nope"] },
          nil_name: error_of { model.Bones.TryGetValue(nil) },
          empty_name: error_of { model.Bones.TryGetValue("") },
          mesh_missing: error_of { model.Meshes["nope"] },
          by_index: model.Bones[1].Name
        }
      end
      puts JSON.generate(out)
    BODY
    assert_equal true, result.fetch("found")
    assert_equal false, result.fetch("wrong_case"), "String.Compare with Ordinal is case-sensitive"
    assert_equal false, result.fetch("absent")
    assert_equal 1, result.fetch("yielded")
    assert_equal 1, result.fetch("item")
    assert_equal "KeyError", result.fetch("item_missing")
    assert_equal "ArgumentError", result.fetch("nil_name")
    assert_equal "ArgumentError", result.fetch("empty_name")
    assert_equal "KeyError", result.fetch("mesh_missing")
    assert_equal "Cube", result.fetch("by_index")
  end

  # The three bone-transform copies, with the IL's two guards on each.
  def test_the_bone_transform_copies_are_the_ils
    skip_unless_fixture

    result = measured(<<~'BODY')
      def error_of
        yield
        "ok"
      rescue StandardError => e
        e.class.name
      end

      out = in_a_game do |host|
        model = host.Content.Load(G::Model, "BlenderDefaultCube")
        relative = ::Array.new(2)
        model.CopyBoneTransformsTo(relative)
        absolute = ::Array.new(2)
        model.CopyAbsoluteBoneTransformsTo(absolute)
        moved = F::Matrix.CreateTranslation(F::Vector3.new(3.0, 4.0, 5.0))
        model.CopyBoneTransformsFrom([moved, F::Matrix.Identity])
        after = ::Array.new(2)
        model.CopyAbsoluteBoneTransformsTo(after)
        {
          relative: relative.map { |m| [m.M41, m.M42, m.M43] },
          absolute: absolute.map { |m| [m.M41, m.M42, m.M43] },
          after: after.map { |m| [m.M41, m.M42, m.M43] },
          round_trip: model.Bones[0].Transform.M41,
          null: error_of { model.CopyBoneTransformsTo(nil) },
          short: error_of { model.CopyBoneTransformsTo(::Array.new(1)) },
          null_from: error_of { model.CopyBoneTransformsFrom(nil) },
          short_from: error_of { model.CopyBoneTransformsFrom([F::Matrix.Identity]) },
          longer_is_fine: error_of { model.CopyBoneTransformsTo(::Array.new(5)) }
        }
      end
      puts JSON.generate(out)
    BODY
    assert_equal [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]], result.fetch("relative")
    assert_equal [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]], result.fetch("absolute")
    # The child bone's absolute transform is its own times its parent's, so moving the root moves
    # both — which is the whole difference between the two copies.
    assert_equal [[3.0, 4.0, 5.0], [3.0, 4.0, 5.0]], result.fetch("after")
    assert_equal 3.0, result.fetch("round_trip")
    assert_equal "ArgumentError", result.fetch("null")
    assert_equal "RangeError", result.fetch("short")
    assert_equal "ArgumentError", result.fetch("null_from")
    assert_equal "RangeError", result.fetch("short_from")
    assert_equal "ok", result.fetch("longer_is_fine"), "the guard is `<`, not `!=`"
  end

  # Both draws reach CNA and both succeed. The managed loop the IL describes is unreachable — see
  # the effect test below — so what is asserted is that the call goes through and that the three
  # managed type checks in `Model.Draw` are still this projection's.
  def test_both_draws_reach_the_native_route_and_the_type_checks_are_managed
    skip_unless_fixture

    result = measured(<<~'BODY')
      def error_of
        yield
        "ok"
      rescue StandardError => e
        e.class.name
      end

      out = in_a_game do |host|
        model = host.Content.Load(G::Model, "BlenderDefaultCube")
        identity = F::Matrix.Identity
        {
          model_draw: error_of { model.Draw(identity, identity, identity) },
          mesh_draw: error_of { model.Meshes[0].Draw },
          not_a_matrix: error_of { model.Draw(1, identity, identity) },
          nil_view: error_of { model.Draw(identity, nil, identity) }
        }
      end
      puts JSON.generate(out)
    BODY
    assert_equal "ok", result.fetch("model_draw")
    assert_equal "ok", result.fetch("mesh_draw")
    assert_equal "TypeError", result.fetch("not_a_matrix")
    assert_equal "TypeError", result.fetch("nil_view")
  end

  # UPSTREAM, recorded from both sides: every generic `Effect` route segfaults on the effect a
  # loaded model publishes, while the `cna_basic_effect_*` routes on the same handle answer
  # correctly. So `Parameters` and `Techniques` are empty here and `CurrentTechnique` is nil, and
  # the raw route is asserted to still fault so the record stays honest if CNA changes.
  def test_a_models_effect_carries_no_parameters_because_the_route_faults
    skip_unless_fixture

    result = measured(<<~'BODY')
      out = in_a_game do |host|
        model = host.Content.Load(G::Model, "BlenderDefaultCube")
        effect = model.Meshes[0].MeshParts[0].Effect
        {
          klass: effect.class.name,
          parameters: effect.Parameters.Count,
          techniques: effect.Techniques.Count,
          current: effect.CurrentTechnique.nil?,
          device: effect.GraphicsDevice.equal?(host.GraphicsDevice)
        }
      end
      puts JSON.generate(out)
    BODY
    assert_equal "Microsoft::Xna::Framework::Graphics::Effect", result.fetch("klass")
    assert_equal 0, result.fetch("parameters")
    assert_equal 0, result.fetch("techniques")
    assert result.fetch("current")
    assert result.fetch("device")
  end

  # The raw route, called with no Ruby object in the path, must still fault. If it stops faulting
  # this fails, and the deviation above comes out with it.
  def test_the_generic_effect_route_still_faults_on_a_model_owned_handle
    skip_unless_fixture

    _output, status = child(<<~'BODY', hard_exit: false)
      require "fiddle"
      in_a_game do |host|
        model = host.Content.Load(G::Model, "BlenderDefaultCube")
        handle = model.Meshes[0].MeshParts[0].Effect.__send__(:native_handle)
        library = CNA::Native.library.instance_variable_get(:@handle)
        route = Fiddle::Function.new(library["cna_effect_get_parameters"],
                                     [Fiddle::TYPE_UINT64_T, Fiddle::TYPE_VOIDP],
                                     Fiddle::TYPE_UINT32_T)
        $stdout.flush
        route.call(handle, Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE))
        nil
      end
      puts "{}"
    BODY
    refute status.success?, "cna_effect_get_parameters no longer faults on a model-owned effect — " \
                            "build the Effect graph again and delete the recorded deviation"
  end

  # The three model-owned resources refuse politely, which is why their wrappers are `PARENT_OWNED`.
  def test_the_model_owned_resources_refuse_their_own_destroy
    skip_unless_fixture

    result = measured(<<~'BODY')
      require "fiddle"
      out = in_a_game do |host|
        model = host.Content.Load(G::Model, "BlenderDefaultCube")
        part = model.Meshes[0].MeshParts[0]
        library = CNA::Native.library.instance_variable_get(:@handle)
        codes = {
          "cna_effect_destroy" => part.Effect,
          "cna_vertex_buffer_destroy" => part.VertexBuffer,
          "cna_index_buffer_destroy" => part.IndexBuffer
        }.to_h do |symbol, object|
          route = Fiddle::Function.new(library[symbol], [Fiddle::TYPE_UINT64_T], Fiddle::TYPE_UINT32_T)
          [symbol, route.call(object.__send__(:native_handle))]
        end
        codes.merge("still_usable" => part.VertexBuffer.VertexCount)
      end
      puts JSON.generate(out)
    BODY
    # CNA_RESULT_INVALID_STATE.
    assert_equal 3, result.fetch("cna_effect_destroy")
    assert_equal 3, result.fetch("cna_vertex_buffer_destroy")
    assert_equal 3, result.fetch("cna_index_buffer_destroy")
    assert_equal 24, result.fetch("still_usable")
  end

  # `ContentManager.Unload` releases the graph's views. It is this binding's own bookkeeping — XNA's
  # `ModelReader` registers the buffers it made as disposable assets instead — and it is what keeps
  # the views from outliving the manager.
  def test_unload_releases_the_graphs_views
    skip_unless_fixture

    result = measured(<<~'BODY')
      out = in_a_game do |host|
        model = host.Content.Load(G::Model, "BlenderDefaultCube")
        before = model.__send__(:instance_variable_get, :@views).length
        host.Content.Unload
        { before: before, after: model.__send__(:instance_variable_get, :@views).length }
      end
      puts JSON.generate(out)
    BODY
    assert_operator result.fetch("before"), :>, 0
    assert_equal 0, result.fetch("after")
  end

  # The nested enumerator is the projected struct, and it walks the backing array exactly once.
  def test_the_nested_enumerator_is_the_projected_struct
    skip_unless_fixture

    result = measured(<<~'BODY')
      out = in_a_game do |host|
        model = host.Content.Load(G::Model, "BlenderDefaultCube")
        enumerator = model.Bones.GetEnumerator
        names = []
        names << enumerator.Current while enumerator.MoveNext
        {
          klass: enumerator.class.name,
          names: names.map(&:Name),
          exhausted: enumerator.MoveNext,
          dispose: enumerator.Dispose.nil?,
          each: model.Meshes.map(&:Name)
        }
      end
      puts JSON.generate(out)
    BODY
    assert_equal "Microsoft::Xna::Framework::Graphics::ModelBoneCollection::Enumerator",
                 result.fetch("klass")
    assert_equal %w[RootNode Cube], result.fetch("names")
    assert_equal false, result.fetch("exhausted")
    assert result.fetch("dispose")
    assert_equal %w[Cube], result.fetch("each")
  end

  # `ModelMeshPart.set_Effect`'s bookkeeping, from the IL: the old effect leaves `parent.Effects`
  # only when no sibling still holds it, and the new one joins only when no sibling already does.
  # The fixture has one part, so the whole scan is exercised by the trivial case and the write is
  # what is checked.
  def test_setting_a_parts_effect_maintains_the_meshs_effect_collection
    skip_unless_fixture

    result = measured(<<~'BODY')
      out = in_a_game do |host|
        model = host.Content.Load(G::Model, "BlenderDefaultCube")
        mesh = model.Meshes[0]
        part = mesh.MeshParts[0]
        original = part.Effect
        replacement = G::BasicEffect.new(host.GraphicsDevice)
        before = mesh.Effects.Count
        part.Effect = replacement
        after = [mesh.Effects.Count, mesh.Effects[0].equal?(replacement)]
        part.Effect = replacement
        idempotent = mesh.Effects.Count
        part.Effect = nil
        cleared = [mesh.Effects.Count, part.Effect.nil?]
        part.Effect = original
        replacement.Dispose
        { before: before, after: after, idempotent: idempotent, cleared: cleared,
          restored: mesh.Effects.Count }
      end
      puts JSON.generate(out)
    BODY
    assert_equal 1, result.fetch("before")
    assert_equal [1, true], result.fetch("after"), "the old effect left and the new one joined"
    assert_equal 1, result.fetch("idempotent"), "a same-value write returns before touching anything"
    assert_equal [0, true], result.fetch("cleared")
    assert_equal 1, result.fetch("restored")
  end
end
