# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"

# Foundation 22 — the XNA exception cluster.
#
# The original XNA 4.0 Windows assemblies were located on this host by exact SHA-256 and
# disassembled with ikdasm. That IL settles what the pinned public metadata could not: every XNA
# exception type declares zero fields, zero methods, and constructors whose entire body is a pure
# forward to its CLR exception base — `ldarg.0 [ldarg.1 [ldarg.2]] call base::.ctor ret` — with no
# message synthesis and no validation. Six of the eight are therefore complete; the two whose
# selected surface carries a protected serialization constructor stay deferred on that BCL cluster.
class XnaExceptionsTest < Minitest::Test
  F = Microsoft::Xna::Framework

  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read)
    .fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  SIGNATURES = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
    .fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  IL = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read).freeze

  PROJECTED = {
    "Microsoft.Xna.Framework.Audio.InstancePlayLimitException" => F::Audio::InstancePlayLimitException,
    "Microsoft.Xna.Framework.Audio.NoAudioHardwareException" => F::Audio::NoAudioHardwareException,
    "Microsoft.Xna.Framework.Audio.NoMicrophoneConnectedException" => F::Audio::NoMicrophoneConnectedException,
    "Microsoft.Xna.Framework.Graphics.DeviceLostException" => F::Graphics::DeviceLostException,
    "Microsoft.Xna.Framework.Graphics.DeviceNotResetException" => F::Graphics::DeviceNotResetException,
    "Microsoft.Xna.Framework.Graphics.NoSuitableGraphicsDeviceException" => F::Graphics::NoSuitableGraphicsDeviceException
  }.freeze

  # ------------------------------------------------------------------- what the IL establishes

  def test_the_pinned_il_shows_every_constructor_is_a_pure_base_forward
    (PROJECTED.keys + %w[Microsoft.Xna.Framework.Content.ContentLoadException
                         Microsoft.Xna.Framework.Storage.StorageDeviceNotConnectedException]).each do |name|
      entry = IL.fetch("types").fetch(name)
      assert_equal 0, entry.fetch("declaredFields"), name
      assert_equal 0, entry.fetch("declaredMethods"), name
      refute entry.fetch("nativeReachable"), name
      assert_equal 4, entry.fetch("constructors").length, name
      assert(entry.fetch("constructors").all? { |ctor| ctor.fetch("pureBaseForward") }, name)
      assert_equal [0, 1, 2, 2], entry.fetch("constructors").map { |ctor| ctor.fetch("leadingArgumentLoads") }, name
      assert_equal %w[public public public], entry.fetch("constructors").first(3).map { |ctor| ctor.fetch("access") }, name
    end

    # The fourth constructor is the serialization one: private on the six, protected on the two.
    PROJECTED.each_key do |name|
      assert_equal "private", IL.fetch("types").fetch(name).fetch("constructors").last.fetch("access"), name
    end
    %w[Microsoft.Xna.Framework.Content.ContentLoadException
       Microsoft.Xna.Framework.Storage.StorageDeviceNotConnectedException].each do |name|
      assert_equal "family", IL.fetch("types").fetch(name).fetch("constructors").last.fetch("access"), name
    end
  end

  def test_each_projected_type_matches_its_pinned_public_contract
    PROJECTED.each_key do |name|
      pinned = REFERENCE.fetch(name)
      selected = SIGNATURES.fetch(name)
      assert_equal pinned.fetch("members"), selected.fetch("members"), name
      assert_equal 3, selected.fetch("members").length, name
      assert(selected.fetch("members").all? { |member| member.fetch("kind") == "constructor" }, name)
      assert_equal [[], ["System.String"], %w[System.String System.Exception]],
                   selected.fetch("members").map { |member| member.fetch("parameters").map { |p| p.fetch("type") } },
                   name
      assert_equal name.split(".").join("::"), selected.fetch("rubyName"), name
    end
  end

  # ------------------------------------------------------------------------- the Ruby projection

  def test_each_type_is_a_ruby_exception_rooted_at_standard_error
    PROJECTED.each do |name, klass|
      assert_equal StandardError, klass.superclass, name
      assert_operator klass, :<, ::Exception, name
      # The two ExternalException-derived types collapse to the same root, as the register says.
      assert_empty klass.public_instance_methods(false), name
      assert_empty klass.protected_instance_methods(false), name
      assert_empty klass.constants(false), name
      # The single initialize comes from the shared construction module, not from the class itself.
      assert_empty klass.private_instance_methods(false), name
      assert klass.private_method_defined?(:initialize), name
      assert_equal CNA::Runtime::XnaExceptionConstruction,
                   klass.instance_method(:initialize).owner, name
    end
  end

  def test_the_three_constructor_shapes_forward_exactly_like_the_il
    PROJECTED.each do |name, klass|
      # `.ctor()` forwards to the base with no message, so the message is the language runtime's
      # own default naming the type, exactly as System.Exception() produces one naming the CLR type.
      assert_equal klass.name, klass.new.message, name
      assert_nil klass.new.cause, name

      # `.ctor(string)` forwards the message unchanged and adds nothing.
      assert_equal "measured", klass.new("measured").message, name
      assert_nil klass.new("measured").cause, name

      # A null message reaches the base as null, which falls back to the default, in both runtimes.
      assert_equal klass.name, klass.new(nil).message, name

      # `.ctor(string, Exception)` forwards both.
      inner = ArgumentError.new("inner")
      chained = klass.new("outer", inner)
      assert_equal "outer", chained.message, name
      assert_same inner, chained.cause, name
      # Construction must not synthesise a stack trace: the CLR leaves StackTrace null until throw.
      assert_nil chained.backtrace, name
      assert_nil klass.new("outer", nil).cause, name
    end
  end

  def test_they_behave_as_ordinary_ruby_exceptions
    PROJECTED.each do |name, klass|
      caught = begin
        raise klass, "thrown"
      rescue StandardError => error
        error
      end
      assert_instance_of klass, caught, name
      assert_equal "thrown", caught.message, name
      refute_empty caught.backtrace, name

      # A cause bound at construction survives being raised.
      inner = RuntimeError.new("root")
      begin
        raise klass.new("thrown", inner)
      rescue StandardError => error
        assert_same inner, error.cause, name
        assert_includes error.full_message(highlight: false, order: :top), "root", name
      end
    end
  end

  def test_an_ambient_exception_does_not_displace_the_declared_inner_exception
    inner = ArgumentError.new("declared")
    PROJECTED.each_value do |klass|
      begin
        raise "ambient"
      rescue StandardError
        assert_same inner, klass.new("outer", inner).cause
      end
    end
  end

  def test_a_non_exception_inner_value_is_rejected
    PROJECTED.each do |name, klass|
      assert_raises(TypeError, name) { klass.new("outer", 42) }
      assert_raises(TypeError, name) { klass.new("outer", "not an exception") }
      assert_raises(ArgumentError, name) { klass.new("outer", ArgumentError.new("i"), :extra) }
    end
  end

  def test_the_cluster_adds_no_audio_graphics_or_storage_runtime
    %i[SoundEffect Microphone AudioEngine WaveBank SoundBank Cue].each do |name|
      refute F::Audio.const_defined?(name, false), "Audio::#{name}"
    end
    %i[GraphicsAdapter RenderTarget2D Effect].each do |name|
      refute F::Graphics.const_defined?(name, false), "Graphics::#{name}"
    end
    refute F.const_defined?(:Storage, false)
    # Foundation 27 opened Content for the five ContentSerializer attributes and nothing else.
    assert_equal %i[ContentSerializerAttribute ContentSerializerCollectionItemNameAttribute
                    ContentSerializerIgnoreAttribute ContentSerializerRuntimeTypeAttribute
                    ContentSerializerTypeVersionAttribute], F::Content.constants(false).sort
    assert_equal 52, CNA::Native::Manifest::FUNCTIONS.length
    assert_equal 63, CNA::Native::Manifest::CONSTANTS.length
  end

  def test_the_shared_construction_module_adds_no_public_surface
    assert_empty CNA::Runtime::XnaExceptionConstruction.instance_methods(false)
    assert_equal [:initialize], CNA::Runtime::XnaExceptionConstruction.private_instance_methods(false)
    assert_equal [:bind_cause], CNA::Runtime::ExceptionSupport.singleton_methods(false).sort & [:bind_cause]
    PROJECTED.each_value do |klass|
      assert_includes klass.ancestors, CNA::Runtime::XnaExceptionConstruction
    end
  end
end
