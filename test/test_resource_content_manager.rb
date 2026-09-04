# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `Content.ResourceContentManager` — two identities, and the first candidate this project's
# dependency frontier ever **selected** rather than merely listed. Once
# `System.Resources.ResourceManager` was collapsed structurally, it had no blocker left at all and
# `SELECTED_NEXT` named it.
class ResourceContentManagerTest < Minitest::Test
  F = Microsoft::Xna::Framework
  C = Microsoft::Xna::Framework::Content
  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Content.ResourceContentManager"

  # A resource set is any object answering `GetObject`, which is the whole of what the collapse says.
  class Resources
    def initialize(map) = @map = map
    def GetObject(name) = @map[name]
  end

  def services = F::GameServiceContainer.new
  def manager(map = { "sound" => "bytes".b }) = C::ResourceContentManager.new(services, Resources.new(map))

  # ------------------------------------------------------------------- the contract, from metadata

  def test_the_contract_is_a_constructor_and_a_protected_override
    contract = REFERENCE.fetch(NAME)
    assert_equal "Microsoft.Xna.Framework.Content.ContentManager", contract.fetch("baseType")
    assert_equal 2, contract.fetch("members").length
    constructor, open_stream = contract.fetch("members")
    assert_equal %w[constructor .ctor], [constructor.fetch("kind"), constructor.fetch("name")]
    assert_equal ["System.IServiceProvider", "System.Resources.ResourceManager"],
                 constructor.fetch("parameters").map { |p| p.fetch("type") }
    assert_equal %w[method OpenStream protected],
                 [open_stream.fetch("kind"), open_stream.fetch("name"), open_stream.fetch("access")]
    assert_equal "System.IO.Stream", open_stream.fetch("returnType")
    assert C::ResourceContentManager < C::ContentManager
    assert_includes C::ResourceContentManager.protected_instance_methods(false), :OpenStream
  end

  def test_the_collapse_that_unblocked_it_and_the_scoreboard
    collapse = CNA::Runtime::BclProjection::STRUCTURAL_COLLAPSE
    assert_includes collapse.keys, "System.Resources.ResourceManager"
    assert_includes collapse.fetch("System.Resources.ResourceManager"), "GetObject"
    # A collapse invents no Ruby constant, which is the whole point of the category.
    refute CNA::Runtime.const_defined?(:ResourceManager, false)
    refute defined?(System)

    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    assert_equal ReviewedScoreboard::BCL_PROJECTED_IDENTITIES, STRICT.fetch("BCL_PROJECTED_IDENTITIES")
    assert_includes STRICT.fetch("completeTypeNames"), NAME
    refute_includes FRONTIER.fetch("dependencyCompleteCandidates").map { |c| c.fetch("name") }, NAME
  end

  # ------------------------------------------------------------------------------ live behaviour

  # `if (resourceManager == null) throw new ArgumentNullException("resourceManager")`, after the base
  # constructor has run — so a null service provider is reported first, by the base.
  def test_the_constructor_validates_both_arguments_in_the_ils_order
    assert_raises(ArgumentError) { C::ResourceContentManager.new(services, nil) }
    assert_raises(ArgumentError) { C::ResourceContentManager.new(nil, Resources.new({})) }
    assert_raises(TypeError) { C::ResourceContentManager.new(services, Object.new) }
    # It inherits the base's state, including the default root directory it never consults.
    assert_equal "", manager.RootDirectory, "the base default, which this type never consults"
  end

  # `resourceManager.GetObject(assetName)`, then two different `ContentLoadException`s: a name the
  # set does not know, and a name whose value is not `byte[]`. `System.Byte[]` projects to a Ruby
  # String, so "not binary" is "not a String".
  def test_open_stream_answers_a_stream_over_the_bytes_and_reports_both_failures
    subject = manager({ "sound" => "hello".b, "text" => 42, "empty" => "".b })
    stream = subject.__send__(:OpenStream, "sound")
    assert_instance_of CNA::Runtime::Stream, stream
    assert_equal 5, stream.Length
    assert_equal false, stream.CanWrite, "a MemoryStream over a byte[] this binding does not own"
    assert_equal true, stream.CanRead
    buffer = +"\0".b * 5
    assert_equal 5, stream.Read(buffer, 0, 5)
    assert_equal "hello", buffer

    missing = assert_raises(C::ContentLoadException) { subject.__send__(:OpenStream, "nope") }
    assert_includes missing.message, "nope"
    not_binary = assert_raises(C::ContentLoadException) { subject.__send__(:OpenStream, "text") }
    assert_includes not_binary.message, "not binary"
    refute_equal missing.message, not_binary.message, "two different failures, as the IL has them"

    assert_equal 0, subject.__send__(:OpenStream, "empty").Length, "an empty resource is still binary"
  end

  def test_it_refuses_an_empty_name_and_a_disposed_manager
    subject = manager
    assert_raises(ArgumentError) { subject.__send__(:OpenStream, nil) }
    assert_raises(ArgumentError) { subject.__send__(:OpenStream, "") }
    # `ContentManager` reports disposal by nulling both stores, so every later member raises the
    # same way the base does -- which is XNA's own mechanism rather than a flag this type adds.
    subject.Dispose
    assert_raises(CNA::DisposedObjectError) { subject.__send__(:OpenStream, "sound") }
  end

  # ------------------------------------------------------------------- and exactly what it does not

  def test_it_reaches_nothing_native_and_adds_no_content_pipeline
    inventory = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read)
    refute inventory.fetch("types").fetch(NAME).fetch("nativeReachable"),
           "its IL reaches no native entry point, which is why no route is bound for it"
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    refute(symbols.any? { |s| s.include?("resource") })
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    # The three reader types left this list when Foundation 104 built them. What **this**
    # milestone claimed is unchanged and is the sentence above it: this type's IL reaches no
    # native entry point, and the reader family it once stood beside is pure managed too -- not
    # one `cna_content_reader_*` route is bound.
    %i[ContentReader ContentTypeReader ContentTypeReaderManager].each do |built|
      assert C.const_defined?(built, false), built.to_s
    end
    refute(symbols.any? { |s| s.start_with?("cna_content_reader_", "cna_content_type_reader_") })
  end
end
