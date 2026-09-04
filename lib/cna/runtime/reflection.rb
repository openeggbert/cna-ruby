# frozen_string_literal: true

module CNA
  module Runtime
    # The Ruby projection of the four `System.Reflection` identities the XNA `Design` family reaches,
    # and the explicit member registry that answers them.
    #
    # These are **BCL language projections**, not XNA types, and none of their methods is an XNA
    # identity.
    #
    # ## Why exactly these four, and not System.Reflection
    #
    # The reach was measured before the projection was written, from the same IL the converters are
    # (`docs/generated/design-converter-inventory.json`). The whole of it is:
    #
    # - `Type.GetField(string)` -- eleven of the twelve converters build their descriptors from it;
    # - `Type.GetProperty(string)` -- `ColorConverter` alone, whose R/G/B/A are properties;
    # - `Type.GetConstructor(Type[])` -- every `ConvertTo` that answers an `InstanceDescriptor`;
    # - `ConstructorInfo.op_Inequality` -- the null test each of those makes before using it;
    # - `MemberInfo.Name`, `MemberInfo.DeclaringType`, `MemberInfo.GetCustomAttributes` --
    #   `MemberPropertyDescriptor`'s constructor and its `ComponentType`;
    # - `FieldInfo.FieldType`/`GetValue`/`SetValue` and `PropertyInfo.PropertyType`/`GetValue`/`SetValue`
    #   -- what `PropertyDescriptor.PropertyType`, `GetValue` and `SetValue` answer for every
    #   descriptor a consumer receives.
    #
    # That is the closure and it terminates there. No `Assembly`, no `MethodInfo`, no `Binder`, no
    # `BindingFlags`, no attribute retrieval beyond the empty array XNA's descriptor constructor
    # asks for -- projecting them would be over-projecting a private implementation dependency,
    # which the admission rule forbids as firmly as it forbids under-projecting inherited surface.
    #
    # ## The registry is explicit, and that is the point
    #
    # `System.Type` projects to Ruby `Module`, and a Ruby `Module` has no fields. So `GetField` has
    # to be answered by something, and the two ways to do it are both wrong: monkey-patching
    # `Module` would put XNA's names on every class in the consumer's program, and scanning
    # `instance_methods` would make the answer depend on what happened to be defined -- and on load
    # order, since a reopened class changes it.
    #
    # This registry is neither. A type's members are **registered explicitly**, once, beside the
    # type that declares them, and a lookup is a hash read. Nothing scans, nothing infers from
    # naming, and cold-loading the converter files in any order produces byte-identical answers,
    # which `test/test_design_converters.rb` asserts by loading them in a shuffled order in a
    # subprocess.
    module Reflection
      # A CLR type identity reduced to the Ruby type `System.Type` projects it to. The three
      # scalars are the ones the Design family names; anything else is already a Ruby Module.
      #
      # **`System.Int32` and `System.Byte` both answer `Integer`**, and that collision is why every
      # reflected member below carries its CLR identity *beside* its Ruby type rather than only the
      # Ruby one. `ColorConverter` asks `Color` for a `(Byte, Byte, Byte, Byte)` constructor;
      # `Color` declares `(Int32, Int32, Int32, Int32)`; the CLR answers **null** and the converter
      # skips its whole `InstanceDescriptor` branch. Resolving that lookup on Ruby types would make
      # the two signatures equal, the lookup succeed, and this binding produce an `InstanceDescriptor`
      # where XNA produces none -- inventing behaviour rather than projecting it. So the *lookup* is
      # by CLR identity, which is what the IL names, and the *answer* a consumer reads is the Ruby
      # type, which is what `System.Type` projects to.
      SCALARS = {"System.Single" => ::Float, "System.Int32" => ::Integer, "System.Byte" => ::Integer}.freeze

      class << self
        # A CLR identity resolves to the Ruby type it projects to. The three scalars are built in;
        # every other identity is registered explicitly by whatever declares it, so this module
        # never has to know what an XNA type is called.
        def register_type_identity(clr_identity, ruby_type)
          existing = type_identities[clr_identity]
          return clr_identity if existing.equal?(ruby_type)
          raise ::ArgumentError, "#{clr_identity} already projects to #{existing}" unless existing.nil?

          type_identities[clr_identity] = ruby_type
          clr_identity
        end

        def ruby_type(clr_identity)
          return clr_identity unless clr_identity.is_a?(::String)

          type_identities.fetch(clr_identity) do
            raise ::ArgumentError, "no Ruby type is projected for #{clr_identity}"
          end
        end

        private

        def type_identities = @type_identities ||= SCALARS.dup
      end

      # The Ruby projection of `System.Reflection.MemberInfo`: the base of everything the three
      # admitted lookups answer, and the declared first parameter of `InstanceDescriptor`'s
      # constructor.
      class MemberInfo
        CLR_IDENTITY = "System.Reflection.MemberInfo"

        attr_reader :Name, :DeclaringType

        def initialize(name, declaringType)
          @Name = name.to_s.dup.freeze
          @DeclaringType = declaringType
        end

        # `MemberPropertyDescriptor`'s constructor calls `GetCustomAttributes(typeof(Attribute), true)`
        # and casts the result to `Attribute[]`. Ruby has no annotation mechanism and this binding
        # attaches no attributes to a projected member, so the honest answer is the empty array --
        # which is what the CLR answers for an XNA value-type field too, every one of which is
        # declared with no custom attribute at all.
        def GetCustomAttributes(_attributeType = nil, _inherit = true) = [].freeze

        # Reflection objects must have stable identity: `InstanceDescriptor` compares the member it
        # was handed, and a descriptor collection is looked up by the descriptor built over one. The
        # registry answers the same instance for the same (type, name) pair, so `equal?` already
        # holds; value equality is defined anyway, because the CLR's does.
        def ==(other)
          other.instance_of?(self.class) && other.Name == @Name && other.DeclaringType.equal?(@DeclaringType)
        end
        alias eql? ==

        def hash = [self.class, @Name, @DeclaringType].hash

        def ToString = "#{@DeclaringType}.#{@Name}"
        alias to_s ToString
      end

      # The Ruby projection of `System.Reflection.FieldInfo`. An XNA value type's `X`, `Min`, `M11`
      # and the rest are CLR *fields*, and this is what `Type.GetField` answers for them.
      #
      # The Ruby side of a projected XNA value type exposes those members as an attribute reader and
      # writer pair -- `Vector3#X` and `Vector3#X=` -- so reading and writing go through the type's
      # own validation rather than around it. That is a deliberate difference from the CLR, where a
      # `FieldInfo.SetValue` writes the field directly: this binding's setters coerce and range-check,
      # and bypassing them would let a descriptor write a value the type refuses from every other
      # direction.
      class FieldInfo < MemberInfo
        CLR_IDENTITY = "System.Reflection.FieldInfo"

        # `FieldType` is the answer a consumer reads and is a Ruby `Module`, because that is what
        # `System.Type` projects to. `clr_field_type` is the identity the pinned metadata declares,
        # kept beside it because `Integer` cannot tell `System.Int32` from `System.Byte` and two
        # measured behaviours turn on that distinction.
        attr_reader :FieldType, :clr_field_type

        def initialize(name, declaringType, clrFieldType)
          super(name, declaringType)
          @clr_field_type = clrFieldType.is_a?(::String) ? clrFieldType.dup.freeze : nil
          @FieldType = Reflection.ruby_type(clrFieldType)
          freeze
        end

        def GetValue(component)
          raise ::ArgumentError, "component" if component.nil?

          component.public_send(@Name)
        end

        def SetValue(component, value)
          raise ::ArgumentError, "component" if component.nil?

          component.public_send("#{@Name}=", value)
          nil
        end
      end

      # The Ruby projection of `System.Reflection.PropertyInfo`, which `Type.GetProperty` answers.
      # `Color.R`, `G`, `B` and `A` are the whole of its reach: they are the one XNA value type
      # whose converter reads properties rather than fields.
      class PropertyInfo < MemberInfo
        CLR_IDENTITY = "System.Reflection.PropertyInfo"

        attr_reader :PropertyType, :clr_property_type

        def initialize(name, declaringType, clrPropertyType, writable: true)
          super(name, declaringType)
          @clr_property_type = clrPropertyType.is_a?(::String) ? clrPropertyType.dup.freeze : nil
          @PropertyType = Reflection.ruby_type(clrPropertyType)
          @writable = writable
          freeze
        end

        def CanWrite = @writable

        # The CLR signature is `GetValue(object, object[])`; the index array is for indexed
        # properties and XNA passes null. It is accepted and ignored rather than dropped, so the
        # arity a consumer sees is the CLR one.
        def GetValue(component, _index = nil)
          raise ::ArgumentError, "component" if component.nil?

          component.public_send(@Name)
        end

        def SetValue(component, value, _index = nil)
          raise ::ArgumentError, "component" if component.nil?
          raise CNA::Runtime::NotSupportedError, "#{@DeclaringType}.#{@Name} has no setter" unless @writable

          component.public_send("#{@Name}=", value)
          nil
        end
      end

      # The Ruby projection of `System.Reflection.ConstructorInfo`: what `Type.GetConstructor(Type[])`
      # answers, and what eleven `ConvertTo` implementations hand an `InstanceDescriptor` after
      # comparing it against null.
      class ConstructorInfo < MemberInfo
        CLR_IDENTITY = "System.Reflection.ConstructorInfo"

        # The CLR name of every constructor.
        NAME = ".ctor"

        # `ParameterTypes` answers Ruby `Module`s, which is what `System.Type[]` projects to;
        # `clr_parameter_types` is the identity list the pinned metadata declares, and is what
        # `GetConstructor` matches on.
        attr_reader :ParameterTypes, :clr_parameter_types

        def initialize(declaringType, clrParameterTypes)
          super(NAME, declaringType)
          @clr_parameter_types = clrParameterTypes.map { |entry| entry.is_a?(::String) ? entry.dup.freeze : entry }.freeze
          @ParameterTypes = clrParameterTypes.map { |entry| Reflection.ruby_type(entry) }.freeze
          freeze
        end

        def GetParameters = @ParameterTypes

        def Invoke(arguments)
          @DeclaringType.new(*Array(arguments))
        end

        def ==(other)
          super && other.clr_parameter_types == @clr_parameter_types
        end
        alias eql? ==

        def hash = [self.class, @DeclaringType, @clr_parameter_types].hash

        def ToString = "Void .ctor(#{@clr_parameter_types.map(&:to_s).join(", ")})"
        alias to_s ToString
      end

      class << self
        # Registers one type's reflected members. Called once, from the file that declares the
        # projection consuming them, and never from a scan.
        #
        # `fields` and `properties` are ordered maps from member name to declared type; `constructors`
        # is a list of parameter-type lists. A second registration of the same type replaces the
        # first rather than merging, so reloading a file is idempotent and cannot accumulate.
        def register(type, fields: {}, properties: {}, constructors: [])
          members = {
            fields: fields.to_h { |name, clr_type| [name.to_s, FieldInfo.new(name, type, clr_type)] }.freeze,
            properties: properties.to_h do |name, clr_type|
              [name.to_s, PropertyInfo.new(name, type, clr_type)]
            end.freeze,
            constructors: constructors.map { |parameters| ConstructorInfo.new(type, parameters) }.freeze
          }.freeze
          registry[type] = members
          type
        end

        # `Type.GetField(string)`. The CLR's default binding finds public instance fields; a name
        # that matches none answers **null**, which is what a Ruby `nil` is here. It never throws.
        def GetField(type, name) = registry.dig(type, :fields)&.[](name.to_s)

        # `Type.GetProperty(string)`, with the same null-on-miss rule.
        def GetProperty(type, name) = registry.dig(type, :properties)&.[](name.to_s)

        # `Type.GetConstructor(Type[])`. The CLR matches on the exact parameter type list and
        # answers **null** when no public instance constructor has it -- which is not a corner case
        # here: `ColorConverter` asks `Color` for a `(Byte, Byte, Byte, Byte)` constructor and
        # `Color` declares none, so the answer really is nil and the converter's own null test is
        # what decides what happens next.
        # The match is on the **CLR** parameter identities the caller names, not on the Ruby types
        # they project to. That is the whole of what keeps `ColorConverter`'s measured answer --
        # `Color` has no four-byte constructor, so this really is nil.
        def GetConstructor(type, clrParameterTypes)
          wanted = Array(clrParameterTypes)
          registry.dig(type, :constructors)&.find { |constructor| constructor.clr_parameter_types == wanted }
        end

        # Whether a type has been registered at all, so a caller can tell "no such member" from
        # "nothing was ever registered for this type" -- two answers the CLR never has to
        # distinguish and a registry does.
        def registered?(type) = registry.key?(type)

        def registered_types = registry.keys

        private

        def registry = @registry ||= {}
      end
    end
  end
end
