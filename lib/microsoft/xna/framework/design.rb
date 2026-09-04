# frozen_string_literal: true

module Microsoft
  module Xna
    module Framework
      # `Microsoft.Xna.Framework.Design` -- the thirteen type converters, and the three private
      # descriptor classes their collections are built from.
      #
      # Every fact below is derived from the pinned original `Microsoft.Xna.Framework.dll` rather
      # than written by hand. `tools/api_compat/build_design_inventory.rb` extracts the audit table
      # -- descriptor names, authored order, sort order, field-versus-property reflection, the
      # scalar element type, whether string conversion is supported, the constructor each
      # `InstanceDescriptor` names and the dictionary keys each `CreateInstance` reads -- into
      # `docs/generated/design-converter-inventory.json`, and `test/test_design_converters.rb`
      # asserts this file against it. Neither side can drift without the other failing.
      #
      # ## Four facts the IL settles that no page had recorded
      #
      # 1. **Sorting decides nothing.** `MatrixConverter` and `RectangleConverter` never call
      #    `PropertyDescriptorCollection.Sort` at all, so their property order is the order the
      #    descriptors were authored in -- `M11..M44` and `X, Y, Width, Height`, neither of them
      #    alphabetical, which is what a bare `Sort()` would have given. And each of the ten that
      #    *do* sort passes exactly the order it just authored, so the sort reorders nothing either.
      #    All twelve answer their authored order, by two paths.
      #
      # 2. **`ColorConverter` cannot produce an `InstanceDescriptor`.** Its `ConvertTo` asks
      #    `typeof(Color).GetConstructor(new[]{ typeof(byte) x4 })`. `Color` declares seven public
      #    constructors and none of them takes four bytes, so `GetConstructor` answers **null**, the
      #    IL's own `ConstructorInfo.op_Inequality(ctor, null)` test at `IL_00bb` fails, and the
      #    branch is skipped entirely. What a consumer gets is the base `TypeConverter.ConvertTo`,
      #    which throws for a non-String destination. That is XNA's behaviour, reproduced rather
      #    than corrected: the generator resolves every named constructor against the reference
      #    contract, eleven of twelve resolve, and this one is reported as not resolving.
      #
      # 3. **Six converters answer `CanConvertTo(String)` true and cannot format one.**
      #    `supportStringConvert` is false for `BoundingBox`, `BoundingSphere`, `Matrix`, `Plane`,
      #    `Ray` and `Rectangle`, so `CanConvertFrom(String)` is false for them -- but `CanConvertTo`
      #    falls through to `TypeConverter.CanConvertTo`, whose whole body is
      #    `destinationType == typeof(string)`. So the answer is **true**, and `ConvertTo` really
      #    does produce a string: the base implementation's, which is `value.ToString()`. A
      #    `MatrixConverter` therefore answers `Matrix.ToString()` where a `Vector3Converter`
      #    answers a separator-joined list.
      #
      # 4. **`TypeConverter.CanConvertFrom` answers for `InstanceDescriptor`, not for `String`.**
      #    Half of each converter's answer is the base class's, which is why the base is projected
      #    rather than flattened: writing those two members from what they appear to do would have
      #    inverted both.
      module Design
        CM = CNA::Runtime::ComponentModel
        RF = CNA::Runtime::Reflection
        GL = CNA::Runtime::Globalization
        private_constant :CM, :RF, :GL

        # ------------------------------------------------------------------ the private descriptors
        #
        # `.class private` in the IL, and private constants here. They are not XNA public surface and
        # must never become one -- the API verifier's leak walk would report a new module under
        # `Microsoft::Xna::Framework` as an `INTERNAL_TYPE_LEAK`, and `private_constant` is what keeps
        # them out of `Module#constants`. What a consumer observes is the `PropertyDescriptor`
        # contract they implement, through the collection `GetProperties` answers.

        # `MemberPropertyDescriptor` -- abstract, over `System.ComponentModel.PropertyDescriptor`.
        # Its constructor passes `member.Name` and `member.GetCustomAttributes(typeof(Attribute), true)`
        # to the base, then stores the member. Five of the base's abstract members get their answer
        # here and are the same for a field and a property: `IsReadOnly` false, `CanResetValue`
        # false, `ResetValue` empty, `ShouldSerializeValue` true, `ComponentType` the member's
        # declaring type. `Equals` and `GetHashCode` both forward to the member.
        class MemberPropertyDescriptor < CM::PropertyDescriptor
          def initialize(member)
            raise ::ArgumentError, "member" if member.nil?

            super(member.Name, member.GetCustomAttributes(CNA::Runtime::Attribute, true))
            @member = member
          end

          def ComponentType = @member.DeclaringType
          def IsReadOnly = false

          # `PropertyDescriptor.Converter` is `TypeDescriptor.GetConverter(PropertyType)`, and for a
          # `Color` channel the CLR answers `ByteConverter`. Ruby's `Integer` is the projection of
          # both `System.Byte` and `System.Int32`, so asking by Ruby type would answer
          # `Int32Converter` for both -- a different converter with a different range. The member
          # carries its CLR identity precisely so this one can be exact, and a member whose type is
          # not one of the three scalars falls back to the type-keyed question.
          def Converter
            identity = clr_member_type
            return CM::TypeDescriptor.scalar_converter(identity) if CM::TypeDescriptor::INTRINSIC.key?(identity)

            super
          end
          def CanResetValue(_component) = false
          def ResetValue(_component) = nil
          def ShouldSerializeValue(_component) = true

          def ==(other)
            other.is_a?(MemberPropertyDescriptor) && other.member == @member
          end
          alias eql? ==

          def hash = @member.hash

          protected

          attr_reader :member

          private

          def clr_member_type = raise(::NotImplementedError, "#{self.class}#clr_member_type")
        end

        # `FieldPropertyDescriptor` -- `PropertyType` is the field's type, `GetValue` reads it and
        # `SetValue` writes it and then calls `OnValueChanged(component, EventArgs.Empty)`, which is
        # measured at `IL_000d`..`IL_0014` and is what makes a subscribed consumer observe the write.
        class FieldPropertyDescriptor < MemberPropertyDescriptor
          def initialize(field)
            super
            @field = field
          end

          def PropertyType = @field.FieldType
          def GetValue(component) = @field.GetValue(component)

          def SetValue(component, value)
            @field.SetValue(component, value)
            OnValueChanged(component, CNA::Runtime::EventArgs::Empty)
            nil
          end

          private

          def clr_member_type = @field.clr_field_type
        end

        # `PropertyPropertyDescriptor` -- the same shape over a property. `ColorConverter` is the one
        # converter that builds these, because `Color`'s R/G/B/A are CLR properties rather than fields.
        class PropertyPropertyDescriptor < MemberPropertyDescriptor
          def initialize(property)
            super
            @property = property
          end

          def PropertyType = @property.PropertyType
          def GetValue(component) = @property.GetValue(component, nil)

          def SetValue(component, value)
            @property.SetValue(component, value, nil)
            OnValueChanged(component, CNA::Runtime::EventArgs::Empty)
            nil
          end

          private

          def clr_member_type = @property.clr_property_type
        end

        private_constant :MemberPropertyDescriptor, :FieldPropertyDescriptor, :PropertyPropertyDescriptor

        # ------------------------------------------------------------------------ MathTypeConverter

        # `MathTypeConverter` extends `System.ComponentModel.ExpandableObjectConverter`, which is
        # projected rather than flattened: `CanConvertFrom` and `CanConvertTo` each answer half of
        # their result from the base class's implementation, so replacing the base with `Object`
        # would mean inventing behaviour rather than deriving it.
        class MathTypeConverter < CM::ExpandableObjectConverter
          # `.field family` in the IL -- protected, not assembly -- so both are in the projected
          # surface and a subclass really can read and write them. `propertyDescriptions` is typed
          # `PropertyDescriptorCollection`, which is why projecting this type at all required the
          # collection to be projected too.
          def initialize
            super
            @supportStringConvert = true
            @propertyDescriptions = nil
          end

          # `CanConvertFrom(context, sourceType)`. The string branch is guarded by
          # `supportStringConvert`; everything else is the base class's answer, which is
          # `sourceType == InstanceDescriptor` and **not** String.
          def CanConvertFrom(*arguments)
            context, sourceType = split_two(arguments, "CanConvertFrom")
            return true if @supportStringConvert && sourceType.equal?(::String)

            super(context, sourceType)
          end

          # `CanConvertTo(context, destinationType)`. `InstanceDescriptor` is the special case at
          # `IL_0001`; the fallback is the base's `destinationType == String`.
          def CanConvertTo(*arguments)
            context, destinationType = split_two(arguments, "CanConvertTo")
            return true if destinationType.equal?(CM::InstanceDescriptor)

            super(context, destinationType)
          end

          def GetCreateInstanceSupported(*arguments)
            CM::ITypeDescriptorContext.check(arguments.first, "GetCreateInstanceSupported") unless arguments.empty?
            true
          end

          def GetPropertiesSupported(*arguments)
            CM::ITypeDescriptorContext.check(arguments.first, "GetPropertiesSupported") unless arguments.empty?
            true
          end

          # The whole body is `ldarg.0; ldfld propertyDescriptions; ret` -- it answers the field and
          # ignores all three arguments, including `value`. So every instance of a converter answers
          # the same collection for every value, which is a contract a consumer can observe: mutating
          # it affects the next caller of the same converter instance.
          def GetProperties(*arguments)
            case arguments.length
            when 1, 2, 3 then CM::ITypeDescriptorContext.check(arguments.first, "GetProperties") if arguments.length > 1
            else raise ::ArgumentError, "GetProperties expects (value), (context, value) or (context, value, attributes)"
            end
            @propertyDescriptions
          end

          protected

          attr_accessor :propertyDescriptions, :supportStringConvert

          private

          def split_two(arguments, member)
            case arguments.length
            when 1 then [nil, arguments[0]]
            when 2 then [CM::ITypeDescriptorContext.check(arguments[0], member), arguments[1]]
            else raise ::ArgumentError, "#{member} expects (type) or (context, type)"
            end
          end

          class << self
            # Both generic helpers are `assembly` in the IL -- internal to the assembly -- so
            # neither may be publicly callable under any spelling. `private` inside `class << self`
            # applies from where it appears, so it opens the block: declaring it after the two
            # methods, which is the shape that reads naturally, would have left both public.
            private

            # `ConvertToValues<T>`. Not XNA public surface, and a consumer must not be able to
            # name it.
            #
            # Measured step by step, because every one of them is observable:
            #
            #   1. `value as string`; a non-string answers **null**, which is what makes each
            #      derived `ConvertFrom` fall through to the base rather than throw.
            #   2. `Trim()` the whole string.
            #   3. a nil culture becomes `CurrentCulture`.
            #   4. split on `culture.TextInfo.ListSeparator` with `StringSplitOptions.None`, so an
            #      empty field is kept and becomes an element that fails to parse.
            #   5. each element goes through `TypeDescriptor.GetConverter(typeof(T)).ConvertFromString`,
            #      **not** through a Ruby primitive parse -- which is what makes hexadecimal work for
            #      the integer converters and not for the single ones.
            #   6. any exception from an element is wrapped in `ArgumentException` carrying it as the
            #      inner exception, with `FrameworkResources.InvalidStringFormat` formatted from the
            #      expected parameter names joined by the separator.
            #   7. the count is checked **after** every element has been converted, so a malformed
            #      element in a wrong-length string still reports the element failure first.
            def convert_to_values(context, culture, value, arrayCount, expectedParams, elementType)
              return nil unless value.is_a?(::String)

              text = value.strip
              culture ||= GL::CultureInfo.CurrentCulture
              separator = culture.TextInfo.ListSeparator
              parts = split_keeping_empty(text, separator)
              converter = CM::TypeDescriptor.scalar_converter(elementType)
              values = parts.map do |part|
                begin
                  converter.ConvertFromString(context, culture, part)
                rescue ::StandardError => error
                  raise ::ArgumentError, invalid_string_format(culture, expectedParams, error)
                end
              end
              return values if values.length == arrayCount

              raise ::ArgumentError, invalid_string_format(culture, expectedParams, nil)
            end

            # `ConvertFromValues<T>` -- also `assembly`. The join separator is the culture's list
            # separator **plus a space**, which is the `String.Concat(listSeparator, " ")` at
            # `IL_0015`..`IL_001a`, while the *split* separator has no space. So a round trip through
            # both is not symmetric in whitespace, and `Trim` on each element is what absorbs it.
            def convert_from_values(context, culture, values, elementType)
              culture ||= GL::CultureInfo.CurrentCulture
              separator = "#{culture.TextInfo.ListSeparator} "
              converter = CM::TypeDescriptor.scalar_converter(elementType)
              values.map { |value| converter.ConvertToString(context, culture, value) }.join(separator)
            end

            # `String.Split(string[], StringSplitOptions.None)`: an empty field between two
            # separators is kept, and so is a trailing one. Ruby's `String#split` drops trailing
            # empty fields unless the limit is negative, which would make `"1,2,"` parse as two
            # values instead of failing on three.
            def split_keeping_empty(text, separator)
              return [text] if separator.empty?

              text.split(separator, -1)
            end

            # `FrameworkResources.InvalidStringFormat` is a localized Microsoft resource string and
            # is not transcribed. What is preserved is the exception identity, the inner exception,
            # and the one fact the CLR message carries: the expected parameter names joined by the
            # culture's list separator.
            def invalid_string_format(culture, expectedParams, inner)
              expected = expectedParams.join(culture.TextInfo.ListSeparator)
              message = "InvalidStringFormat: expected #{expected}"
              inner.nil? ? message : "#{message} (#{inner.class}: #{inner.message})"
            end
          end
        end

        # ----------------------------------------------------------------- the twelve derived types
        #
        # Each is generated from one row of the audit table, so what differs between them is data
        # rather than code: the value type, the descriptor members and how they are reflected, the
        # authored and sorted orders, the scalar element type, whether string conversion is
        # supported, and the constructor parameter list the `InstanceDescriptor` branch names.

        # The row shape, kept beside the converters it builds so the correspondence with the
        # generated table is one line per fact.
        Row = Struct.new(:valueType, :members, :reflection, :sortOrder, :supportStringConvert,
                         :elementType, :constructorParameters, :declaresConvertFrom, keyword_init: true)
        private_constant :Row

        # `nil` for `sortOrder` means the constructor never calls `Sort`, which is `MatrixConverter`
        # and `RectangleConverter` and nothing else. `elementType` nil means the converter declares
        # no string conversion path at all.
        MATRIX_MEMBERS = %w[M11 M12 M13 M14 M21 M22 M23 M24 M31 M32 M33 M34 M41 M42 M43 M44].freeze
        private_constant :MATRIX_MEMBERS

        ROWS = {
          "BoundingBoxConverter" => Row.new(
            valueType: "BoundingBox", members: %w[Min Max], reflection: :GetField,
            sortOrder: %w[Min Max], supportStringConvert: false, elementType: nil,
            constructorParameters: %w[Vector3 Vector3], declaresConvertFrom: true
          ),
          "BoundingSphereConverter" => Row.new(
            valueType: "BoundingSphere", members: %w[Center Radius], reflection: :GetField,
            sortOrder: %w[Center Radius], supportStringConvert: false, elementType: nil,
            constructorParameters: ["Vector3", "System.Single"], declaresConvertFrom: true
          ),
          "ColorConverter" => Row.new(
            valueType: "Color", members: %w[R G B A], reflection: :GetProperty,
            sortOrder: %w[R G B A], supportStringConvert: true, elementType: "System.Byte",
            constructorParameters: ["System.Byte"] * 4, declaresConvertFrom: true
          ),
          "MatrixConverter" => Row.new(
            valueType: "Matrix", members: MATRIX_MEMBERS, reflection: :GetField,
            sortOrder: nil, supportStringConvert: false, elementType: nil,
            constructorParameters: ["System.Single"] * 16, declaresConvertFrom: false
          ),
          "PlaneConverter" => Row.new(
            valueType: "Plane", members: %w[Normal D], reflection: :GetField,
            sortOrder: %w[Normal D], supportStringConvert: false, elementType: nil,
            constructorParameters: ["Vector3", "System.Single"], declaresConvertFrom: false
          ),
          "PointConverter" => Row.new(
            valueType: "Point", members: %w[X Y], reflection: :GetField,
            sortOrder: %w[X Y], supportStringConvert: true, elementType: "System.Int32",
            constructorParameters: ["System.Int32"] * 2, declaresConvertFrom: true
          ),
          "QuaternionConverter" => Row.new(
            valueType: "Quaternion", members: %w[X Y Z W], reflection: :GetField,
            sortOrder: %w[X Y Z W], supportStringConvert: true, elementType: "System.Single",
            constructorParameters: ["System.Single"] * 4, declaresConvertFrom: true
          ),
          "RayConverter" => Row.new(
            valueType: "Ray", members: %w[Position Direction], reflection: :GetField,
            sortOrder: %w[Position Direction], supportStringConvert: false, elementType: nil,
            constructorParameters: %w[Vector3 Vector3], declaresConvertFrom: true
          ),
          "RectangleConverter" => Row.new(
            valueType: "Rectangle", members: %w[X Y Width Height], reflection: :GetField,
            sortOrder: nil, supportStringConvert: false, elementType: nil,
            constructorParameters: ["System.Int32"] * 4, declaresConvertFrom: false
          ),
          "Vector2Converter" => Row.new(
            valueType: "Vector2", members: %w[X Y], reflection: :GetField,
            sortOrder: %w[X Y], supportStringConvert: true, elementType: "System.Single",
            constructorParameters: ["System.Single"] * 2, declaresConvertFrom: true
          ),
          "Vector3Converter" => Row.new(
            valueType: "Vector3", members: %w[X Y Z], reflection: :GetField,
            sortOrder: %w[X Y Z], supportStringConvert: true, elementType: "System.Single",
            constructorParameters: ["System.Single"] * 3, declaresConvertFrom: true
          ),
          "Vector4Converter" => Row.new(
            valueType: "Vector4", members: %w[X Y Z W], reflection: :GetField,
            sortOrder: %w[X Y Z W], supportStringConvert: true, elementType: "System.Single",
            constructorParameters: ["System.Single"] * 4, declaresConvertFrom: true
          )
        }.freeze

        # `ROWS` and `REFLECTED` below are this file's own workings -- one row per generated audit
        # entry, and the reflected member tables the descriptors are built from. Neither is an XNA
        # identity, so both are private constants for the same reason the three descriptor classes
        # are: `Microsoft::Xna::Framework::Design` must expose the thirteen converters and nothing
        # else. `test_design_converters.rb` asserts that, and reads them back with `const_get`,
        # which is the one accessor `private_constant` deliberately does not close.
        #
        # The CLR identity of a Ruby scalar or XNA value type, for the constructor lookup. The three
        # scalars are the ones the audit table names; everything else is an XNA type in this
        # namespace's parent.
        # Every reflected type is addressed by its **CLR identity**, scalar or XNA alike, so the
        # lookup can tell `System.Int32` from `System.Byte` -- two identities Ruby's `Integer`
        # cannot separate and one measured behaviour turns on. The XNA identities are registered
        # with the reflection module here, once, so nothing there has to know what an XNA type is.
        def self.clr_identity(name) = "Microsoft.Xna.Framework.#{name}"

        %w[Point Rectangle Vector2 Vector3 Vector4 Quaternion Matrix Plane Ray BoundingBox
           BoundingSphere Color].each do |name|
          RF.register_type_identity(clr_identity(name), Microsoft::Xna::Framework.const_get(name))
        end

        def self.clr_or_xna(identity)
          case identity
          when "System.Single", "System.Int32", "System.Byte" then identity
          else clr_identity(identity)
          end
        end

        # ------------------------------------------------------------- the reflected member registry
        #
        # `System.Type` projects to Ruby `Module`, and a Module has no fields, so `Type.GetField`,
        # `GetProperty` and `GetConstructor` have to be answered by something. Registering the
        # members explicitly, here, once, is what makes that answer deterministic: nothing scans
        # `instance_methods`, nothing infers from a naming convention, and no `Module` anywhere in
        # the consumer's program is monkey-patched. Cold-loading in any order gives byte-identical
        # answers, which `test/test_design_converters.rb` asserts in a subprocess with a shuffled
        # require order.
        #
        # Each entry names the CLR member type, which is what `PropertyDescriptor.PropertyType`
        # answers and therefore what `PropertyDescriptor.Converter` resolves through. The
        # constructor lists are the ones the audit table says each `InstanceDescriptor` branch asks
        # for -- **including `Color`'s four-byte one, which is deliberately absent**, because that
        # is the fact `ColorConverter`'s null test turns on.
        REFLECTED = {
          "Point" => {fields: {"X" => "System.Int32", "Y" => "System.Int32"},
                      constructors: [["System.Int32"] * 2]},
          "Rectangle" => {fields: {"X" => "System.Int32", "Y" => "System.Int32",
                                   "Width" => "System.Int32", "Height" => "System.Int32"},
                          constructors: [["System.Int32"] * 4]},
          "Vector2" => {fields: {"X" => "System.Single", "Y" => "System.Single"},
                        constructors: [["System.Single"] * 2]},
          "Vector3" => {fields: {"X" => "System.Single", "Y" => "System.Single", "Z" => "System.Single"},
                        constructors: [["System.Single"] * 3]},
          "Vector4" => {fields: {"X" => "System.Single", "Y" => "System.Single",
                                 "Z" => "System.Single", "W" => "System.Single"},
                        constructors: [["System.Single"] * 4]},
          "Quaternion" => {fields: {"X" => "System.Single", "Y" => "System.Single",
                                    "Z" => "System.Single", "W" => "System.Single"},
                           constructors: [["System.Single"] * 4]},
          "Matrix" => {fields: MATRIX_MEMBERS.to_h { |member| [member, "System.Single"] },
                       constructors: [["System.Single"] * 16]},
          "Plane" => {fields: {"Normal" => "Vector3", "D" => "System.Single"},
                      constructors: [["Vector3", "System.Single"]]},
          "Ray" => {fields: {"Position" => "Vector3", "Direction" => "Vector3"},
                    constructors: [%w[Vector3 Vector3]]},
          "BoundingBox" => {fields: {"Min" => "Vector3", "Max" => "Vector3"},
                            constructors: [%w[Vector3 Vector3]]},
          "BoundingSphere" => {fields: {"Center" => "Vector3", "Radius" => "System.Single"},
                               constructors: [["Vector3", "System.Single"]]},
          # `Color`'s channels are CLR **properties**, not fields, which is why `ColorConverter`
          # alone builds `PropertyPropertyDescriptor`s. Its registered constructors are the two the
          # reference contract declares that take four arguments' worth of channel data; the
          # four-byte one XNA's `ColorConverter` asks for is not among them, and `Color` really does
          # not declare it.
          "Color" => {properties: {"R" => "System.Byte", "G" => "System.Byte",
                                   "B" => "System.Byte", "A" => "System.Byte"},
                      constructors: [["System.Int32"] * 3, ["System.Int32"] * 4,
                                     ["System.Single"] * 3, ["System.Single"] * 4]}
        }.freeze

        # Registered as **CLR identities**, not as Ruby types. `Reflection` reduces each to the Ruby
        # type a consumer reads and keeps the identity for the lookup, which is what preserves
        # `Color`'s missing four-byte constructor as a real answer rather than a collision.
        REFLECTED.each do |name, members|
          type = Microsoft::Xna::Framework.const_get(name)
          RF.register(
            type,
            fields: (members[:fields] || {}).transform_values { |identity| clr_or_xna(identity) },
            properties: (members[:properties] || {}).transform_values { |identity| clr_or_xna(identity) },
            constructors: members.fetch(:constructors).map { |list| list.map { |identity| clr_or_xna(identity) } }
          )
        end

        ROWS.each do |converter_name, row|
          value_type = Microsoft::Xna::Framework.const_get(row.valueType)
          parameters = row.constructorParameters.map { |identity| clr_or_xna(identity) }

          converter = Class.new(MathTypeConverter) do
            define_method(:initialize) do
              super()
              self.supportStringConvert = row.supportStringConvert
              descriptors = row.members.map do |member|
                info = RF.public_send(row.reflection, value_type, member)
                raise "#{row.valueType} has no #{row.reflection} #{member}" if info.nil?

                row.reflection == :GetField ? FieldPropertyDescriptor.new(info) : PropertyPropertyDescriptor.new(info)
              end
              collection = CM::PropertyDescriptorCollection.new(descriptors)
              # Ten of the twelve sort; `MatrixConverter` and `RectangleConverter` do not, and their
              # property order is the authored one. `Sort` answers a **new** collection, so the
              # unsorted one is discarded rather than reordered.
              self.propertyDescriptions = row.sortOrder ? collection.Sort(row.sortOrder) : collection
            end

            # `ConvertFrom` is declared by nine of the twelve. For the six that support string
            # conversion it parses; for `BoundingBox`, `BoundingSphere` and `Ray` its whole body is
            # a call to `TypeConverter.ConvertFrom`, which accepts an `InstanceDescriptor` and
            # nothing else. The three that declare none -- `Matrix`, `Plane`, `Rectangle` -- inherit
            # that same behaviour, so all twelve behave identically for an `InstanceDescriptor`
            # source and only the six differ for a String.
            if row.declaresConvertFrom && row.elementType
              define_method(:ConvertFrom) do |*arguments|
                context, culture, value = case arguments.length
                                          when 1 then [nil, GL::CultureInfo.CurrentCulture, arguments[0]]
                                          when 3 then [CM::ITypeDescriptorContext.check(arguments[0], "ConvertFrom"),
                                                       arguments[1], arguments[2]]
                                          else raise ::ArgumentError, "ConvertFrom expects (value) or (context, culture, value)"
                                          end
                values = MathTypeConverter.send(:convert_to_values, context, culture, value,
                                                row.members.length, row.members, row.elementType)
                return value_type.new(*values) unless values.nil?

                super(context, culture, value)
              end
            end

            define_method(:ConvertTo) do |*arguments|
              context, culture, value, destinationType =
                case arguments.length
                when 2 then [nil, GL::CultureInfo.CurrentCulture, arguments[0], arguments[1]]
                when 4 then [CM::ITypeDescriptorContext.check(arguments[0], "ConvertTo"),
                             arguments[1], arguments[2], arguments[3]]
                else raise ::ArgumentError, "ConvertTo expects (value, destinationType) or (context, culture, value, destinationType)"
                end
              # Every derived ConvertTo opens with this, before any other test.
              raise ::ArgumentError, "destinationType" if destinationType.nil?

              if row.elementType && destinationType.equal?(::String) && value.is_a?(value_type)
                return MathTypeConverter.send(:convert_from_values, context, culture,
                                              row.members.map { |member| value.public_send(member) },
                                              row.elementType)
              end

              if destinationType.equal?(CM::InstanceDescriptor) && value.is_a?(value_type)
                constructor = RF.GetConstructor(value_type, parameters)
                # `ConstructorInfo.op_Inequality(ctor, null)`. `ColorConverter` is the one converter
                # for which this is false, because `Color` declares no four-byte constructor, and
                # the whole branch is then skipped.
                unless constructor.nil?
                  return CM::InstanceDescriptor.new(constructor, row.members.map { |member| value.public_send(member) })
                end
              end

              super(context, culture, value, destinationType)
            end

            define_method(:CreateInstance) do |*arguments|
              _context, propertyValues = case arguments.length
                                        when 1 then [nil, arguments[0]]
                                        when 2 then [CM::ITypeDescriptorContext.check(arguments[0], "CreateInstance"),
                                                     arguments[1]]
                                        else raise ::ArgumentError, "CreateInstance expects (propertyValues) or (context, propertyValues)"
                                        end
              # `ArgumentNullException("propertyValues", FrameworkResources.NullNotAllowed)`.
              raise ::ArgumentError, "propertyValues: NullNotAllowed" if propertyValues.nil?

              value_type.new(*row.members.map { |member| propertyValues[member] })
            end
          end

          const_set(converter_name, converter)
          # Registered here, once, beside the converter that answers for the type. Nothing scans and
          # nothing infers from a name, so cold-loading in any order gives the same answers.
          CM::TypeDescriptor.register_converter(value_type, converter)
        end

        private_constant :ROWS, :REFLECTED

        # The property collection `TypeDescriptor.GetProperties(value)` answers for an XNA value
        # type: the same descriptors, in the same order, that the type's own converter carries. A
        # fresh collection per call, because a caller mutating one must not affect the next.
        ROWS.each do |converter_name, row|
          value_type = Microsoft::Xna::Framework.const_get(row.valueType)
          CM::TypeDescriptor.register_properties(value_type) do
            const_get(converter_name).new.GetProperties(nil, nil, nil)
          end
        end

        private_class_method :clr_identity, :clr_or_xna
      end
    end
  end
end
