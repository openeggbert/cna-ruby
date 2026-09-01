# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# Foundation 27 — the five ContentSerializer attributes, and the System.Attribute projection.
#
# Ruby has no annotation mechanism, so a CLR attribute projects as an ordinary data-carrying class
# over the CNA::Runtime::Attribute marker base. Nothing in this binding reads an attribute: there is
# no ContentManager, ContentReader, ContentTypeReader, XNB support or content pipeline of any kind.
class ContentAttributesTest < Minitest::Test
  F = Microsoft::Xna::Framework
  C = F::Content

  ROOT = Pathname(__dir__).join("..").expand_path
  IL = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read).freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze

  NAMES = %w[
    Microsoft.Xna.Framework.Content.ContentSerializerAttribute
    Microsoft.Xna.Framework.Content.ContentSerializerCollectionItemNameAttribute
    Microsoft.Xna.Framework.Content.ContentSerializerIgnoreAttribute
    Microsoft.Xna.Framework.Content.ContentSerializerRuntimeTypeAttribute
    Microsoft.Xna.Framework.Content.ContentSerializerTypeVersionAttribute
  ].freeze

  def test_every_attribute_is_complete_pure_managed_and_rooted_at_the_projection_base
    NAMES.each do |name|
      entry = IL.fetch("types").fetch(name)
      refute entry.fetch("nativeReachable"), name
      assert_equal "Microsoft.Xna.Framework.dll", entry.fetch("assembly"), name
      assert_includes STRICT.fetch("completeTypeNames"), name, name
      assert_equal 0, STRICT.fetch("localDiagnostics").fetch(name), name

      runtime = name.split(".").reduce(Object) { |scope, part| scope.const_get(part, false) }
      assert_equal CNA::Runtime::Attribute, runtime.superclass, name
    end
    # The marker base declares nothing of its own: none of the five inherits a member from it.
    assert_empty CNA::Runtime::Attribute.public_instance_methods(false)
    assert_equal Object, CNA::Runtime::Attribute.superclass
    assert_equal "CNA::Runtime::Attribute", CNA::Runtime::BclProjection::TYPES.fetch("System.Attribute")
  end

  # Foundation 49 added ContentLoadException to the same namespace from its own IL and its own BCL
  # cluster, and the ContentManager projection later added ContentManager; this milestone neither
  # implies nor produces either, which is why both are named here rather than the list being loosened.
  def test_the_content_namespace_holds_exactly_the_five_attributes
    assert_equal %i[ContentSerializerAttribute ContentSerializerCollectionItemNameAttribute
                    ContentSerializerIgnoreAttribute ContentSerializerRuntimeTypeAttribute
                    ContentSerializerTypeVersionAttribute],
                 (C.constants(false) - %i[ContentLoadException ContentManager]).sort
    %i[ContentReader ContentTypeReader ContentTypeReaderManager
       ResourceContentManager].each do |absent|
      refute C.const_defined?(absent, false), "Content::#{absent}"
    end
  end

  # --------------------------------------------------------------- ContentSerializerAttribute

  def test_the_constructor_stores_allow_null_true_and_leaves_everything_else_default
    attribute = C::ContentSerializerAttribute.new
    assert_nil attribute.ElementName
    assert_equal false, attribute.FlattenContent
    assert_equal false, attribute.Optional
    # The only store the constructor makes, before it even calls the base constructor.
    assert_equal true, attribute.AllowNull
    assert_equal false, attribute.SharedResource
  end

  def test_collection_item_name_answers_the_item_literal_until_one_is_set
    attribute = C::ContentSerializerAttribute.new
    # `IsNullOrEmpty` on the raw field answers the literal "Item" instead.
    assert_equal "Item", attribute.CollectionItemName
    assert_equal false, attribute.HasCollectionItemName

    attribute.CollectionItemName = "Entry"
    assert_equal "Entry", attribute.CollectionItemName
    assert_equal true, attribute.HasCollectionItemName
  end

  def test_the_collection_item_name_setter_rejects_null_or_empty
    attribute = C::ContentSerializerAttribute.new
    # ArgumentNullException, which this binding maps to ArgumentError, is thrown for null *and*
    # empty, so TypeError would be wrong for half its cases.
    error = assert_raises(ArgumentError) { attribute.CollectionItemName = "" }
    assert_equal "value", error.message
    assert_raises(ArgumentError) { attribute.CollectionItemName = nil }
    assert_raises(TypeError) { attribute.CollectionItemName = 5 }
    # The rejected assignment leaves the previous value in place.
    assert_equal "Item", attribute.CollectionItemName
  end

  def test_element_name_is_a_plain_store_the_clr_never_inspects
    attribute = C::ContentSerializerAttribute.new
    attribute.ElementName = ""
    assert_equal "", attribute.ElementName
    attribute.ElementName = nil
    assert_nil attribute.ElementName
  end

  def test_the_boolean_setters_take_only_true_or_false
    attribute = C::ContentSerializerAttribute.new
    %i[FlattenContent= Optional= AllowNull= SharedResource=].each do |setter|
      attribute.public_send(setter, true)
      attribute.public_send(setter, false)
      assert_raises(TypeError, setter) { attribute.public_send(setter, 1) }
      assert_raises(TypeError, setter) { attribute.public_send(setter, nil) }
    end
  end

  def test_clone_copies_the_raw_fields_rather_than_the_item_default
    attribute = C::ContentSerializerAttribute.new
    attribute.ElementName = "Node"
    attribute.FlattenContent = true
    attribute.Optional = true
    attribute.AllowNull = false
    attribute.SharedResource = true
    attribute.CollectionItemName = "Entry"

    copy = attribute.Clone
    refute_same copy, attribute
    assert_instance_of C::ContentSerializerAttribute, copy
    %i[ElementName FlattenContent Optional AllowNull SharedResource CollectionItemName
       HasCollectionItemName].each do |name|
      assert_equal attribute.public_send(name), copy.public_send(name), name.to_s
    end

    # A clone of a default instance copies the *raw* null, so it still answers the "Item" default
    # and still reports no collection item name.
    fresh = C::ContentSerializerAttribute.new.Clone
    assert_equal "Item", fresh.CollectionItemName
    assert_equal false, fresh.HasCollectionItemName
    assert_equal true, fresh.AllowNull

    copy.ElementName = "Changed"
    assert_equal "Node", attribute.ElementName
  end

  # ------------------------------------------------------------------------- the other four

  def test_the_single_argument_attributes_validate_exactly_where_the_il_does
    assert_equal "Entry", C::ContentSerializerCollectionItemNameAttribute.new("Entry").CollectionItemName
    assert_equal "Foo", C::ContentSerializerRuntimeTypeAttribute.new("Foo").RuntimeType

    {C::ContentSerializerCollectionItemNameAttribute => "collectionItemName",
     C::ContentSerializerRuntimeTypeAttribute => "runtimeType"}.each do |klass, argument|
      error = assert_raises(ArgumentError, klass.name) { klass.new("") }
      assert_equal argument, error.message
      assert_raises(ArgumentError, klass.name) { klass.new(nil) }
      assert_raises(TypeError, klass.name) { klass.new(5) }
      assert_raises(ArgumentError, klass.name) { klass.new }
      # Get-only: this one has no "Item" fallback of its own.
      refute klass.method_defined?(:"#{argument[0].upcase}#{argument[1..]}=")
    end
  end

  def test_the_ignore_attribute_declares_nothing_but_its_constructor
    attribute = C::ContentSerializerIgnoreAttribute.new
    assert_instance_of C::ContentSerializerIgnoreAttribute, attribute
    assert_empty C::ContentSerializerIgnoreAttribute.public_instance_methods(false)
    assert_equal 0, IL.fetch("types")
                     .fetch("Microsoft.Xna.Framework.Content.ContentSerializerIgnoreAttribute")
                     .fetch("declaredFields")
  end

  def test_the_type_version_attribute_is_the_only_one_that_validates_nothing
    assert_equal 3, C::ContentSerializerTypeVersionAttribute.new(3).TypeVersion
    # The IL stores whatever it is given, so negative and zero versions are accepted.
    assert_equal(-3, C::ContentSerializerTypeVersionAttribute.new(-3).TypeVersion)
    assert_equal 0, C::ContentSerializerTypeVersionAttribute.new(0).TypeVersion
    # Only this binding's Int32 boundary applies.
    assert_raises(RangeError) { C::ContentSerializerTypeVersionAttribute.new(2**31) }
    assert_raises(TypeError) { C::ContentSerializerTypeVersionAttribute.new("3") }
  end

  def test_the_cluster_adds_no_content_pipeline
    # `TitleContainer` and `SpriteFont` exist now; what this milestone claimed, and still claims,
    # is that **it** built no pipeline. The native census below is what measures that, and it is the
    # assertion that has survived every later milestone unchanged.
    refute F::Content.const_defined?(:ContentReader, false)
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:constants), CNA::Native::Manifest::CONSTANTS.length
  end
end
