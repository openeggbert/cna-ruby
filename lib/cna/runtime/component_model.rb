# frozen_string_literal: true

module CNA
  module Runtime
    # The Ruby projection of the seven `System.ComponentModel` identities the XNA `Design` family
    # reaches, measured from the pinned Microsoft .NET Framework 4.0 `System.dll` admitted at
    # Foundation 105 (`docs/generated/bcl-inventory.json`, authority `System`).
    #
    # These are **BCL language projections**, not XNA types. They live in the CNA runtime rather
    # than a fabricated Ruby `::System` namespace, exactly as `ReadOnlyCollection` and `Stream` do,
    # and no method they declare is an XNA identity. Nothing here enters `REFERENCE_TYPES`.
    #
    # ## What is projected, and by which rule
    #
    # The admission rule has two halves and they pull in opposite directions: do not under-project
    # the **inherited public surface**, and do not over-project a **private implementation
    # dependency**. Each family below is placed by which it is:
    #
    # - `TypeConverter` and `ExpandableObjectConverter` are the base chain of `MathTypeConverter`,
    #   so every public member they declare is callable on all thirteen XNA converters. The whole
    #   public surface is projected -- seventeen names, thirty-six CLR overloads -- because a
    #   consumer holding a `Vector3Converter` really can call every one of them.
    # - `PropertyDescriptor` is the base of the three private XNA descriptor classes, and a consumer
    #   receives instances of those from `GetProperties`. Same rule, same conclusion.
    # - `PropertyDescriptorCollection` and `InstanceDescriptor` are objects the converters *answer*.
    #   Everything public on them is reachable on the instance a consumer holds.
    # - `TypeDescriptor` is a static utility, inherited by nothing. Only the members the measured
    #   behaviour calls are projected: `GetConverter` and `GetProperties`. Its other seventy public
    #   statics are the .NET designer's provider ecosystem, which nothing in the reach touches.
    # - `ITypeDescriptorContext` is an interface with **no XNA implementer**, so the structural
    #   collapse the register applies to `IDisposable` and `IServiceProvider` cannot apply: there is
    #   no implementing type whose members it could survive as. It projects to a Ruby module
    #   declaring the contract, and a validator that refuses an object missing any of it.
    module ComponentModel
      # The Ruby projection of `System.ComponentModel.ITypeDescriptorContext`.
      #
      # The CLR interface declares three properties -- `Container`, `Instance`, `PropertyDescriptor`
      # -- and two methods, `OnComponentChanging` and `OnComponentChanged`, and it extends
      # `System.IServiceProvider`, which contributes `GetService`. Six identities, all measured from
      # the admitted `System.dll` rather than remembered.
      #
      # Ruby has no interfaces, and the collapse rule this register applies elsewhere does not fit:
      # `IDisposable` survives as the `Dispose` its implementers declare because XNA declares
      # twenty-nine of them, and here XNA implements the interface nowhere at all. The **consumer**
      # supplies the context. So the projection is a module a consumer may include, plus a check
      # that whatever is supplied answers every required member -- because the alternative,
      # accepting any object and failing later at the call site, is precisely the "silently accept
      # arbitrary objects with missing required methods" this projection refuses.
      #
      # Nil is always accepted: every XNA converter member takes a `context` that the CLR allows to
      # be null, and `TypeConverter`'s own one-argument overloads pass null themselves.
      module ITypeDescriptorContext
        CLR_IDENTITY = "System.ComponentModel.ITypeDescriptorContext"

        # The six identities a context has to answer, measured from the admitted System.dll.
        REQUIRED = %i[Container Instance PropertyDescriptor OnComponentChanging OnComponentChanged
                      GetService].freeze

        # `System.ComponentModel.IContainer` is the declared type of `Container` and nothing in the
        # admitted reach calls a member of it: the converters never read `Container`, and this
        # binding only ever passes the value through. Inventing a Ruby constant for it would add an
        # identity the CLR contract has and nothing here could measure, which is the same reasoning
        # `System.IServiceProvider` and `System.IDisposable` already record.
        CONTAINER_IS_OPAQUE =
          "System.ComponentModel.IContainer is the declared type of Container and no member of it " \
          "is reached; the value is whatever the consumer's context answers and this binding passes it through"

        # Raises unless `context` is nil or answers the whole measured contract. Returns the context
        # so it can be used inline.
        def self.check(context, member)
          return context if context.nil?

          missing = REQUIRED.reject { |name| context.respond_to?(name) }
          return context if missing.empty?

          raise ::ArgumentError,
                "#{member}: an ITypeDescriptorContext must answer #{REQUIRED.join(", ")}; " \
                "this one is missing #{missing.join(", ")}"
        end
      end

      # The Ruby projection of `System.ComponentModel.TypeConverter`.
      #
      # Every behaviour below is read out of the admitted System.dll. The four that matter most,
      # because `MathTypeConverter` and its twelve subclasses fall through to them:
      #
      # - `CanConvertFrom(context, sourceType)` answers `sourceType == InstanceDescriptor` -- **not**
      #   String. So a converter with `supportStringConvert` false answers false for a String source.
      # - `CanConvertTo(context, destinationType)` answers `destinationType == String`. So *every*
      #   converter answers true for a String destination, including the six that cannot format one
      #   themselves.
      # - `ConvertFrom(context, culture, value)` invokes an `InstanceDescriptor` and throws for
      #   anything else. That is why three XNA converters declare a `ConvertFrom` whose whole body
      #   is a call to this one: accepting an `InstanceDescriptor` is the behaviour they want.
      # - `ConvertTo(..., String)` answers `String.Empty` for nil, `value.ToString(null, culture)`
      #   when the value is `IFormattable` and the culture is neither nil nor the current one, and
      #   `value.ToString()` otherwise. That is why `MatrixConverter.ConvertTo(m, String)` answers
      #   `Matrix.ToString()` rather than a separator-joined list.
      class TypeConverter
        CLR_IDENTITY = "System.ComponentModel.TypeConverter"

        # `CanConvertFrom(Type)` and `CanConvertFrom(ITypeDescriptorContext, Type)`. The CLR's
        # one-argument overload forwards with a null context; Ruby has no overloading, so one method
        # takes both shapes and the retained CLR identities are the two signatures.
        def CanConvertFrom(*arguments)
          _context, sourceType = split_context(arguments, "CanConvertFrom")
          sourceType.equal?(InstanceDescriptor)
        end

        def CanConvertTo(*arguments)
          _context, destinationType = split_context(arguments, "CanConvertTo")
          destinationType.equal?(::String)
        end

        # `ConvertFrom(object)` resolves the culture to `CurrentCulture` and the context to nil;
        # `ConvertFrom(context, culture, value)` is the virtual one everything else overrides.
        def ConvertFrom(*arguments)
          # The context and the culture are both split out and neither is read: the CLR body
          # tests the value's type and nothing else. Dropping them from the split would lose the
          # arity check that decides which overload was called.
          _context, _culture, value = split_culture(arguments, "ConvertFrom")
          return value.Invoke if value.is_a?(InstanceDescriptor)

          raise GetConvertFromException(value)
        end

        def ConvertTo(*arguments)
          _context, culture, value, destinationType = split_convert_to(arguments, "ConvertTo")
          raise ::ArgumentError, "destinationType" if destinationType.nil?
          return convert_to_string(culture, value) if destinationType.equal?(::String)

          raise GetConvertToException(value, destinationType)
        end

        # `ConvertFromString` is `ConvertFrom` with a String argument; the CLR declares three
        # overloads and every one of them lands in the same virtual method.
        def ConvertFromString(*arguments)
          case arguments.length
          when 1 then ConvertFrom(nil, Globalization::CultureInfo.CurrentCulture, arguments[0])
          when 2 then ConvertFrom(arguments[0], Globalization::CultureInfo.CurrentCulture, arguments[1])
          when 3 then ConvertFrom(arguments[0], arguments[1], arguments[2])
          else raise ::ArgumentError, "ConvertFromString expects (text), (context, text) or (context, culture, text)"
          end
        end

        def ConvertToString(*arguments)
          case arguments.length
          when 1 then ConvertTo(nil, Globalization::CultureInfo.CurrentCulture, arguments[0], ::String)
          when 2 then ConvertTo(arguments[0], Globalization::CultureInfo.CurrentCulture, arguments[1], ::String)
          when 3 then ConvertTo(arguments[0], arguments[1], arguments[2], ::String)
          else raise ::ArgumentError, "ConvertToString expects (value), (context, value) or (context, culture, value)"
          end
        end

        def ConvertFromInvariantString(*arguments)
          text = arguments.last
          context = arguments.length > 1 ? arguments.first : nil
          ConvertFrom(context, Globalization::CultureInfo.InvariantCulture, text)
        end

        def ConvertToInvariantString(*arguments)
          value = arguments.last
          context = arguments.length > 1 ? arguments.first : nil
          ConvertTo(context, Globalization::CultureInfo.InvariantCulture, value, ::String)
        end

        # `CreateInstance(IDictionary)` answers null in the base; a converter that supports it
        # overrides. `System.Collections.IDictionary` projects to a Ruby Hash, which is what a
        # consumer supplies and what `get_Item` reads.
        def CreateInstance(*arguments)
          _context, _propertyValues = split_context(arguments, "CreateInstance")
          nil
        end

        def GetCreateInstanceSupported(*arguments)
          ITypeDescriptorContext.check(arguments.first, "GetCreateInstanceSupported") unless arguments.empty?
          false
        end

        # `GetProperties(object)`, `(context, object)` and `(context, object, Attribute[])`. The
        # base answers null; `ExpandableObjectConverter` overrides it and `MathTypeConverter`
        # overrides that.
        def GetProperties(*arguments)
          _context, _value, _attributes = split_get_properties(arguments, "GetProperties")
          nil
        end

        def GetPropertiesSupported(*arguments)
          ITypeDescriptorContext.check(arguments.first, "GetPropertiesSupported") unless arguments.empty?
          false
        end

        # `GetStandardValues` answers **null** in the base and no XNA converter overrides it, so
        # every one of the thirteen answers nil. `TypeConverter+StandardValuesCollection` is
        # deliberately **not** projected for that reason: no consumer of this binding can obtain
        # one, and a Ruby class nothing can produce would be an invented identity.
        def GetStandardValues(*arguments)
          ITypeDescriptorContext.check(arguments.first, "GetStandardValues") unless arguments.empty?
          nil
        end

        def GetStandardValuesExclusive(*arguments)
          ITypeDescriptorContext.check(arguments.first, "GetStandardValuesExclusive") unless arguments.empty?
          false
        end

        def GetStandardValuesSupported(*arguments)
          ITypeDescriptorContext.check(arguments.first, "GetStandardValuesSupported") unless arguments.empty?
          false
        end

        # `IsValid` asks whether `ConvertFrom` would succeed. The CLR body tries the conversion and
        # answers false if it threw, which is exactly what this does.
        def IsValid(*arguments)
          context, value = split_context(arguments, "IsValid")
          begin
            ConvertFrom(context, Globalization::CultureInfo.CurrentCulture, value)
            true
          rescue ::StandardError
            false
          end
        end

        # `GetConvertFromException` and `GetConvertToException` are `family` in the CLR and both
        # answer a `NotSupportedException`. The message is a localized `System.SR` resource string,
        # which is Microsoft's and is not transcribed; what is preserved is the exception identity
        # and the two facts the CLR message names -- this converter's type name and the value's.
        def GetConvertFromException(value)
          name = value.nil? ? "(null)" : value.class.name
          CNA::Runtime::NotSupportedError.new("#{self.class.name} cannot convert from #{name}")
        end

        def GetConvertToException(value, destinationType)
          name = value.nil? ? "(null)" : value.class.name
          CNA::Runtime::NotSupportedError.new("#{self.class.name} cannot convert from #{name} to #{destinationType}")
        end

        private

        # The CLR's String branch, exactly: empty string for nil; the culture-aware
        # `IFormattable.ToString(null, culture)` when a culture other than the current one was given
        # and the value is formattable; `value.ToString()` otherwise.
        #
        # `System.IFormattable` declares one member, `ToString(string, IFormatProvider)`, so the
        # projected test for it is whether the value answers a two-argument `ToString` -- the same
        # collapse `System.Action`1` records, applied to a test rather than to a parameter. No XNA
        # value type implements `IFormattable`, and none answers a two-argument `ToString`, so the
        # two agree exactly over the surface this binding projects.
        #
        # They disagree in one place, and it is recorded rather than special-cased: the CLR's
        # `Single` **is** `IFormattable` and Ruby's `Float`, which `System.Single` projects to, is
        # not. So this base member answers `1.5` where the CLR answers `1,5` for a German culture.
        # Nothing in the Design family reaches it -- the three scalar element converters override
        # `ConvertTo` and do the culture work themselves -- and special-casing numerics here would
        # be inventing a rule the CLR does not have, whose rule is the interface.
        def convert_to_string(culture, value)
          return "" if value.nil?

          if !culture.nil? && !culture.equal?(Globalization::CultureInfo.CurrentCulture) &&
             value.respond_to?(:ToString) && value.method(:ToString).arity != 0
            return value.ToString(nil, culture)
          end

          value.respond_to?(:ToString) ? value.ToString : value.to_s
        end

        # A CLR overload pair `(x)` / `(context, x)` collapses to one Ruby method. Which shape was
        # used is decided by arity alone, never by sniffing the first argument's type -- a context
        # is any object answering the protocol, and guessing would make a legitimate one-argument
        # call ambiguous.
        def split_context(arguments, member)
          case arguments.length
          when 1 then [nil, arguments[0]]
          when 2 then [ITypeDescriptorContext.check(arguments[0], member), arguments[1]]
          else raise ::ArgumentError, "#{member} expects (value) or (context, value)"
          end
        end

        def split_culture(arguments, member)
          case arguments.length
          when 1 then [nil, Globalization::CultureInfo.CurrentCulture, arguments[0]]
          when 3 then [ITypeDescriptorContext.check(arguments[0], member), arguments[1], arguments[2]]
          else raise ::ArgumentError, "#{member} expects (value) or (context, culture, value)"
          end
        end

        def split_convert_to(arguments, member)
          case arguments.length
          when 2 then [nil, Globalization::CultureInfo.CurrentCulture, arguments[0], arguments[1]]
          when 4 then [ITypeDescriptorContext.check(arguments[0], member), arguments[1], arguments[2], arguments[3]]
          else raise ::ArgumentError, "#{member} expects (value, destinationType) or (context, culture, value, destinationType)"
          end
        end

        def split_get_properties(arguments, member)
          case arguments.length
          when 1 then [nil, arguments[0], nil]
          when 2 then [ITypeDescriptorContext.check(arguments[0], member), arguments[1], nil]
          when 3 then [ITypeDescriptorContext.check(arguments[0], member), arguments[1], arguments[2]]
          else raise ::ArgumentError, "#{member} expects (value), (context, value) or (context, value, attributes)"
          end
        end
      end

      # The Ruby projection of `System.ComponentModel.ExpandableObjectConverter`.
      #
      # Measured, not assumed empty: it declares exactly three identities and overrides two
      # behaviours. `GetProperties(context, value, attributes)` **ignores the context** and forwards
      # to `TypeDescriptor.GetProperties(value, attributes)`; `GetPropertiesSupported(context)`
      # answers true unconditionally. Its constructor is a pure forward to the base.
      class ExpandableObjectConverter < TypeConverter
        CLR_IDENTITY = "System.ComponentModel.ExpandableObjectConverter"

        def GetProperties(*arguments)
          _context, value, attributes = *split_expandable(arguments)
          TypeDescriptor.GetProperties(value, attributes)
        end

        def GetPropertiesSupported(*arguments)
          ITypeDescriptorContext.check(arguments.first, "GetPropertiesSupported") unless arguments.empty?
          true
        end

        private

        def split_expandable(arguments)
          case arguments.length
          when 1 then [nil, arguments[0], nil]
          when 2 then [ITypeDescriptorContext.check(arguments[0], "GetProperties"), arguments[1], nil]
          when 3 then [ITypeDescriptorContext.check(arguments[0], "GetProperties"), arguments[1], arguments[2]]
          else raise ::ArgumentError, "GetProperties expects (value), (context, value) or (context, value, attributes)"
          end
        end
      end

      # The Ruby projection of `System.ComponentModel.PropertyDescriptor`.
      #
      # Abstract in the CLR and abstract here: `PropertyType`, `GetValue` and `SetValue` have no
      # implementation of their own, and `ComponentType`, `IsReadOnly`, `CanResetValue`,
      # `ResetValue` and `ShouldSerializeValue` are abstract too -- XNA's `MemberPropertyDescriptor`
      # supplies all five. Ruby has no abstract keyword, so each raises `NotImplementedError`, which
      # is the convention this binding already uses for an interface member with no implementation.
      #
      # `Name` and the attribute surface come from the CLR base `System.ComponentModel.MemberDescriptor`.
      # That class is **not** separately projected: the whole of it that the admitted reach touches
      # is `Name` -- `PropertyDescriptorCollection.Find` and `Sort` compare on it and XNA's
      # descriptor constructor sets it -- and `Attributes`, which is the empty array a projected
      # member carries. Collapsing one intermediate BCL level into its subclass is the same
      # documented decision `ExternalException` records in the projection register.
      class PropertyDescriptor
        CLR_IDENTITY = "System.ComponentModel.PropertyDescriptor"

        attr_reader :Name, :Attributes

        def initialize(name, attributes = nil)
          raise ::ArgumentError, "name" if name.nil? || name.to_s.empty?

          @Name = name.to_s.dup.freeze
          @Attributes = (attributes || []).dup.freeze
          @value_changed = {}
        end

        # ------------------------------------------------------------------ the abstract surface

        def ComponentType = raise(::NotImplementedError, "#{self.class}#ComponentType")
        def PropertyType = raise(::NotImplementedError, "#{self.class}#PropertyType")
        def IsReadOnly = raise(::NotImplementedError, "#{self.class}#IsReadOnly")
        def GetValue(_component) = raise(::NotImplementedError, "#{self.class}#GetValue")
        def SetValue(_component, _value) = raise(::NotImplementedError, "#{self.class}#SetValue")
        def CanResetValue(_component) = raise(::NotImplementedError, "#{self.class}#CanResetValue")
        def ResetValue(_component) = raise(::NotImplementedError, "#{self.class}#ResetValue")
        def ShouldSerializeValue(_component) = raise(::NotImplementedError, "#{self.class}#ShouldSerializeValue")

        # ------------------------------------------------------------------ the concrete surface

        # `Converter` answers `TypeDescriptor.GetConverter(PropertyType)`, which is how a designer
        # walks from a descriptor to the converter for the member's own type.
        def Converter = TypeDescriptor.GetConverter(self.PropertyType)

        # Attribute-driven in the CLR, and this binding attaches no attributes to a projected
        # member, so each answers the value the CLR answers when the attribute is absent.
        def IsLocalizable = false
        def SerializationVisibility = :Visible
        def SupportsChangeEvents = false

        # `GetChildProperties` forwards to `TypeDescriptor.GetProperties`, in all four CLR overload
        # shapes.
        def GetChildProperties(*arguments)
          case arguments.length
          when 0 then TypeDescriptor.GetProperties(self.PropertyType, nil)
          when 1 then arguments[0].is_a?(::Array) ? TypeDescriptor.GetProperties(self.PropertyType, arguments[0])
                                                  : TypeDescriptor.GetProperties(arguments[0], nil)
          when 2 then TypeDescriptor.GetProperties(arguments[0], arguments[1])
          else raise ::ArgumentError, "GetChildProperties expects (), (attributes), (instance) or (instance, attributes)"
          end
        end

        # `GetEditor(Type)` consults the designer's editor providers. This binding registers none,
        # which is not a gap: the CLR answers null too when nothing has registered an editor for the
        # type, and nothing in the admitted reach registers one.
        def GetEditor(_editorBaseType) = nil

        # The change-notification pair. `FieldPropertyDescriptor.SetValue` and
        # `PropertyPropertyDescriptor.SetValue` both call `OnValueChanged(component, EventArgs.Empty)`
        # after writing, so a consumer that subscribed really does observe the write. The CLR keys
        # the handler list by component, and so does this.
        def AddValueChanged(component, handler)
          raise ::ArgumentError, "component" if component.nil?
          raise ::ArgumentError, "handler" if handler.nil?

          (@value_changed[component.object_id] ||= []) << handler
          nil
        end

        def RemoveValueChanged(component, handler)
          raise ::ArgumentError, "component" if component.nil?
          raise ::ArgumentError, "handler" if handler.nil?

          list = @value_changed[component.object_id]
          return nil if list.nil?

          index = list.rindex(handler)
          list.delete_at(index) unless index.nil?
          @value_changed.delete(component.object_id) if list.empty?
          nil
        end

        # `family` in the CLR, and reached: XNA's two concrete descriptors call it from `SetValue`.
        def OnValueChanged(component, args)
          return nil if component.nil?

          (@value_changed[component.object_id] || []).dup.each { |handler| handler.call(component, args) }
          nil
        end

        def Equals(other) = self == other
        def GetHashCode = hash
        def ToString = @Name
        alias to_s ToString
      end

      # The Ruby projection of `System.ComponentModel.PropertyDescriptorCollection`.
      #
      # This is the object `MathTypeConverter.GetProperties` answers, so the whole of its public
      # surface is reachable on an instance a consumer holds, and all of it is projected. Every
      # behaviour is measured from the admitted System.dll:
      #
      # - `Find(name, ignoreCase)` is a **linear scan in collection order**, first match wins, and
      #   answers nil when nothing matches. Case-sensitive comparison is ordinal; the ignore-case
      #   one is `StringComparison.OrdinalIgnoreCase` -- the operand is `ldc.i4.5` -- so it is *not*
      #   culture-aware, which matters for a culture whose casing rules differ from the invariant.
      # - `Sort` answers a **new collection** and never reorders the receiver. Four overloads, and
      #   each of them constructs a fresh collection carrying the requested order.
      # - `Sort(names)` puts the named descriptors first **in the order given**, then everything
      #   else in the default order -- which is `String.Compare(a.Name, b.Name, false, InvariantCulture)`,
      #   the comparison `TypeDescriptor.SortDescriptorArray` performs through its
      #   `MemberDescriptorComparer`. Eleven of the twelve XNA converters pass names covering every
      #   descriptor they authored, so the tail is empty for them; `MatrixConverter` and
      #   `RectangleConverter` never call `Sort` at all and keep their authored order.
      # - The collection built by `.ctor(PropertyDescriptor[])` is **mutable**: `readOnly` defaults
      #   to false, so `Add`, `Remove`, `Insert`, `Clear` and `RemoveAt` work on the object XNA's
      #   converters hand back. The two-argument constructor is what makes one read-only, and then
      #   every mutating member throws `NotSupportedException`.
      class PropertyDescriptorCollection
        include ::Enumerable

        CLR_IDENTITY = "System.ComponentModel.PropertyDescriptorCollection"

        def initialize(properties, readOnly = false)
          raise ::ArgumentError, "properties" if properties.nil?

          @properties = properties.dup
          @readOnly = readOnly ? true : false
          @namedSort = nil
          @comparer = nil
          @sorted = true
        end

        # `PropertyDescriptorCollection.Empty` -- a read-only, empty, shared instance, as the CLR's
        # `initonly` static field is.
        def self.Empty
          @Empty ||= new([].freeze, true)
        end

        def Count
          ensure_sorted
          @properties.length
        end

        # `get_Item(int32)` and `get_Item(string)`. The CLR indexer by integer throws
        # `IndexOutOfRangeException` out of range, which this binding projects to Ruby's
        # `IndexError`; the indexer by name answers **nil** when nothing matches, because it is
        # `Find(name, false)`.
        def [](index)
          ensure_sorted
          return Find(index, false) if index.is_a?(::String) || index.is_a?(::Symbol)
          raise ::IndexError, "index #{index} is outside 0...#{@properties.length}" unless index.is_a?(::Integer)
          raise ::IndexError, "index #{index} is outside 0...#{@properties.length}" if index.negative? || index >= @properties.length

          @properties[index]
        end

        def Find(name, ignoreCase)
          ensure_sorted
          wanted = name.to_s
          @properties.find do |descriptor|
            ignoreCase ? descriptor.Name.casecmp(wanted).zero? : descriptor.Name == wanted
          end
        end

        def Contains(descriptor)
          ensure_sorted
          @properties.any? { |entry| entry.equal?(descriptor) || entry == descriptor }
        end

        def IndexOf(descriptor)
          ensure_sorted
          @properties.index { |entry| entry.equal?(descriptor) || entry == descriptor } || -1
        end

        def Add(descriptor)
          refuse_if_read_only
          ensure_sorted
          @properties << descriptor
          @properties.length - 1
        end

        def Insert(index, descriptor)
          refuse_if_read_only
          ensure_sorted
          raise ::IndexError, "index #{index} is outside 0..#{@properties.length}" if index.negative? || index > @properties.length

          @properties.insert(index, descriptor)
          nil
        end

        def Remove(descriptor)
          refuse_if_read_only
          ensure_sorted
          index = IndexOf(descriptor)
          @properties.delete_at(index) unless index.negative?
          nil
        end

        def RemoveAt(index)
          refuse_if_read_only
          ensure_sorted
          raise ::IndexError, "index #{index} is outside 0...#{@properties.length}" if index.negative? || index >= @properties.length

          @properties.delete_at(index)
          nil
        end

        def Clear
          refuse_if_read_only
          @properties.clear
          nil
        end

        # `CopyTo(Array, int)`. A destination that cannot hold the source raises `ArgumentError`,
        # the rule `CurveKeyCollection` established for the whole binding.
        def CopyTo(destination, index)
          ensure_sorted
          raise ::ArgumentError, "array" if destination.nil?
          raise ::ArgumentError, "index" if index.negative?
          raise ::ArgumentError, "the destination cannot hold #{@properties.length} descriptors from #{index}" if destination.length - index < @properties.length

          @properties.each_with_index { |descriptor, offset| destination[index + offset] = descriptor }
          nil
        end

        # All four `Sort` overloads answer a **new** collection; none reorders the receiver. Each
        # keeps whichever of the two ordering inputs it was not given, because the CLR constructs
        # the new collection with `(properties, propCount, namedSort, comparer)` in every one of
        # them -- so `Sort()` on a collection that already carries a comparer keeps that comparer
        # rather than falling back to the default ordering.
        def Sort(*arguments)
          case arguments.length
          when 0 then sorted_copy(@namedSort, @comparer)
          when 1 then arguments[0].is_a?(::Array) || arguments[0].nil? ? sorted_copy(arguments[0], @comparer)
                                                                       : sorted_copy(@namedSort, arguments[0])
          when 2 then sorted_copy(arguments[0], arguments[1])
          else raise ::ArgumentError, "Sort expects (), (names), (comparer) or (names, comparer)"
          end
        end

        def GetEnumerator
          ensure_sorted
          @properties.each
        end

        def each(&block)
          ensure_sorted
          return @properties.each unless block

          @properties.each(&block)
          self
        end

        def IsReadOnly = @readOnly
        def ToString = "#{self.class.name}(#{Count})"
        alias to_s ToString

        protected

        # Applying the requested order is deferred until the collection is read, exactly as the CLR
        # defers it: `Sort` builds a collection carrying a `namedSort`, and the order materialises on
        # first access.
        def prepare(namedSort, comparer)
          @namedSort = namedSort
          @comparer = comparer
          @sorted = false
          self
        end

        private

        def sorted_copy(namedSort, comparer)
          ensure_sorted
          self.class.new(@properties, @readOnly).send(:prepare, namedSort, comparer)
        end

        def ensure_sorted
          return if @sorted

          @sorted = true
          # `InternalSort` sorts by the default comparison first, then lifts the named descriptors
          # to the front in the order they were named. Doing it the other way round would leave the
          # unnamed tail in insertion order rather than alphabetical order.
          @properties = if @comparer
                          @properties.sort { |left, right| @comparer.call(left, right) }
                        else
                          default_sort(@properties)
                        end
          return if @namedSort.nil? || @namedSort.empty?

          remaining = @properties.dup
          ordered = []
          @namedSort.each do |name|
            index = remaining.index { |descriptor| !descriptor.nil? && descriptor.Name == name.to_s }
            next if index.nil?

            ordered << remaining[index]
            remaining[index] = nil
          end
          @properties = ordered + remaining.compact
        end

        # `TypeDescriptor.SortDescriptorArray`'s comparison, measured: an ordinal,
        # case-**sensitive** `String.Compare` against the invariant culture.
        def default_sort(list) = list.sort { |left, right| left.Name <=> right.Name }

        def refuse_if_read_only
          return unless @readOnly

          raise CNA::Runtime::NotSupportedError, "this PropertyDescriptorCollection is read-only"
        end
      end

      # The Ruby projection of `System.ComponentModel.Design.Serialization.InstanceDescriptor`.
      #
      # Sealed in the CLR and sealed here in effect. It is what `MathTypeConverter.CanConvertTo`
      # special-cases -- the `ldtoken` at `IL_0001` -- and what eleven of the twelve derived
      # `ConvertTo` implementations construct. `MemberInfo` is a `ConstructorInfo` in every one of
      # those eleven; `Arguments` is the `object[]` of member values, which
      # `System.Collections.ICollection` projects to a Ruby Array.
      #
      # `IsComplete` says whether the arguments fully describe the instance. The two-argument
      # constructor sets it true, which is the one XNA uses, so every descriptor the converters
      # produce is complete.
      class InstanceDescriptor
        CLR_IDENTITY = "System.ComponentModel.Design.Serialization.InstanceDescriptor"

        attr_reader :MemberInfo, :Arguments, :IsComplete

        def initialize(memberInfo, arguments, isComplete = true)
          @MemberInfo = memberInfo
          @Arguments = (arguments || []).dup.freeze
          @IsComplete = isComplete ? true : false
          freeze
        end

        # `Invoke` reconstructs the instance the descriptor describes. For a `ConstructorInfo` that
        # is `ctor.Invoke(Arguments)`; the CLR also allows a field, property or method member, none
        # of which the admitted reach ever produces, so a member that is not a constructor is a
        # refusal rather than an invented path.
        def Invoke
          return nil if @MemberInfo.nil?
          unless @MemberInfo.is_a?(CNA::Runtime::Reflection::ConstructorInfo)
            raise CNA::Runtime::NotSupportedError,
                  "InstanceDescriptor.Invoke supports a ConstructorInfo member; this one is #{@MemberInfo.class}"
          end

          @MemberInfo.Invoke(@Arguments)
        end

        def ToString = "InstanceDescriptor(#{@MemberInfo}, #{@Arguments.length} arguments)"
        alias to_s ToString
      end

      # The Ruby projection of `System.ComponentModel.BaseNumberConverter` and the three element
      # converters that derive from it.
      #
      # `MathTypeConverter` parses and formats no number itself. `ConvertToValues<T>` calls
      # `TypeDescriptor.GetConverter(typeof(T))` at `IL_0054` and `ConvertFromValues<T>` at
      # `IL_002a`, and every scalar in every string the thirteen converters produce or accept goes
      # through the converter that answers. Which converter that is is measured:
      # `ReflectTypeDescriptionProvider`'s intrinsic table, extracted into
      # `docs/generated/bcl-inventory.json`, says `System.Int32` -> `Int32Converter`,
      # `System.Single` -> `SingleConverter`, `System.Byte` -> `ByteConverter`.
      #
      # Two behaviours differ between them and both are observable:
      #
      # - **Hexadecimal.** `BaseNumberConverter.AllowHex` answers `ldc.i4.1` -- true -- and
      #   `SingleConverter` overrides it to `ldc.i4.0`. So `PointConverter.ConvertFrom("#10, #20")`
      #   parses hex and `Vector2Converter.ConvertFrom("#10, #20")` does not. The four accepted
      #   prefixes are `#`, `0x`, `0X`, `&h` and `&H`, read from the `ldstr` operands.
      # - **The number styles.** `Single.Parse` is called with `0xa7` --
      #   `NumberStyles.Float | AllowThousands` -- and `Int32.Parse`/`Byte.Parse` with `7`,
      #   `NumberStyles.Integer`. So a decimal point is a parse failure for the integer converters
      #   and a group separator is accepted by all three.
      class BaseNumberConverter < TypeConverter
        CLR_IDENTITY = "System.ComponentModel.BaseNumberConverter"

        # `ldc.i4.1` in the CLR getter; `SingleConverter` is the one override.
        def AllowHex = true

        # The prefixes the CLR tests for, in the order it tests them. `#` is checked first, on the
        # first character; the other four are `StartsWith` tests.
        HEX_PREFIXES = ["0x", "0X", "&h", "&H"].freeze

        def ConvertFrom(*arguments)
          _context, culture, value = split_culture(arguments, "ConvertFrom")
          return super unless value.is_a?(::String)

          text = value.strip
          if self.AllowHex && !text.empty?
            return from_string(text[1..], 16) if text[0] == "#"

            prefix = HEX_PREFIXES.find { |candidate| text.start_with?(candidate) }
            return from_string(text[2..], 16) if prefix
          end
          from_string(text, culture || Globalization::CultureInfo.CurrentCulture)
        rescue ::ArgumentError, ::TypeError, ::RangeError => error
          raise CNA::Runtime::NotSupportedError,
                "#{self.class.name} cannot convert #{value.inspect}: #{error.message}"
        end

        def ConvertTo(*arguments)
          _context, culture, value, destinationType = split_convert_to(arguments, "ConvertTo")
          raise ::ArgumentError, "destinationType" if destinationType.nil?
          return super unless destinationType.equal?(::String) && target?(value)

          to_string(value, culture || Globalization::CultureInfo.CurrentCulture)
        end

        private

        def target?(_value) = raise(::NotImplementedError, "#{self.class}#target?")
        def from_string(_text, _radix_or_culture) = raise(::NotImplementedError, "#{self.class}#from_string")
        def to_string(_value, _culture) = raise(::NotImplementedError, "#{self.class}#to_string")

        # The culture-aware digits of an integral parse: `NumberStyles.Integer` is leading and
        # trailing white space plus a leading sign, and nothing else -- no decimal point, no
        # exponent. The group separator is not in `NumberStyles.Integer`, so it is *not* stripped.
        def parse_integer(text, culture)
          body = text.strip
          raise ::ArgumentError, "empty" if body.empty?

          sign = 1
          if body.start_with?(culture.NegativeSign)
            sign = -1
            body = body[culture.NegativeSign.length..]
          elsif body.start_with?(culture.PositiveSign)
            body = body[culture.PositiveSign.length..]
          end
          raise ::ArgumentError, "#{text.inspect} is not an integer" unless body.match?(/\A\d+\z/)

          sign * Integer(body, 10)
        end

        # `NumberStyles.Float | NumberStyles.AllowThousands`: white space, a leading sign, the
        # culture's decimal separator, an exponent, and the culture's group separator.
        def parse_single(text, culture)
          body = text.strip
          raise ::ArgumentError, "empty" if body.empty?
          return Float::NAN if body == culture.NaNSymbol
          return Float::INFINITY if body == culture.PositiveInfinitySymbol
          return -Float::INFINITY if body == culture.NegativeInfinitySymbol

          sign = 1
          if body.start_with?(culture.NegativeSign)
            sign = -1
            body = body[culture.NegativeSign.length..]
          elsif body.start_with?(culture.PositiveSign)
            body = body[culture.PositiveSign.length..]
          end
          body = body.gsub(culture.NumberGroupSeparator, "") unless culture.NumberGroupSeparator.empty?
          # The decimal separator is the culture's, and `Float()` only understands ".". Replacing it
          # is the whole of the culture dependence, and it must be the *only* separator accepted:
          # a "." in a culture whose decimal separator is "," is a parse failure, not a second
          # spelling, which is what makes the culture tests able to fail.
          unless culture.NumberDecimalSeparator == "."
            raise ::ArgumentError, "#{text.inspect} is not a number in #{culture.Name}" if body.include?(".")

            body = body.sub(culture.NumberDecimalSeparator, ".")
          end
          raise ::ArgumentError, "#{text.inspect} is not a number" unless body.match?(/\A\d*\.?\d+(?:[eE][-+]?\d+)?\z\
|\A\d+\.?\d*(?:[eE][-+]?\d+)?\z/)

          sign * Float(body)
        end
      end

      # `TypeDescriptor.GetConverter(typeof(Int32))`. `Int32Converter.ToString` formats with `"G"`,
      # which for an integer is its plain decimal spelling.
      class Int32Converter < BaseNumberConverter
        CLR_IDENTITY = "System.ComponentModel.Int32Converter"

        private

        def target?(value) = value.is_a?(::Integer)

        def from_string(text, radix_or_culture)
          value = radix_or_culture == 16 ? Integer(text, 16) : parse_integer(text, radix_or_culture)
          CNA::Runtime::Numeric.int32(value, "value")
        end

        def to_string(value, culture)
          digits = value.abs.to_s
          value.negative? ? "#{culture.NegativeSign}#{digits}" : digits
        end
      end

      # `TypeDescriptor.GetConverter(typeof(Byte))`. Same `"G"` formatting; the difference from
      # `Int32Converter` is the range, and a value outside 0..255 is a conversion failure rather
      # than a wrap.
      class ByteConverter < BaseNumberConverter
        CLR_IDENTITY = "System.ComponentModel.ByteConverter"

        private

        def target?(value) = value.is_a?(::Integer)

        def from_string(text, radix_or_culture)
          value = radix_or_culture == 16 ? Integer(text, 16) : parse_integer(text, radix_or_culture)
          CNA::Runtime::Numeric.uint8(value, "value")
        end

        def to_string(value, culture)
          digits = value.abs.to_s
          value.negative? ? "#{culture.NegativeSign}#{digits}" : digits
        end
      end

      # `TypeDescriptor.GetConverter(typeof(Single))`. Two overrides from the base, both measured:
      # `AllowHex` answers false, and `ToString` formats with `"R"` rather than `"G"`.
      class SingleConverter < BaseNumberConverter
        CLR_IDENTITY = "System.ComponentModel.SingleConverter"

        def AllowHex = false

        private

        def target?(value) = value.is_a?(::Float) || value.is_a?(::Integer)

        def from_string(text, radix_or_culture)
          raise ::ArgumentError, "SingleConverter does not accept hexadecimal" if radix_or_culture == 16

          CNA::Runtime::Numeric.f32(parse_single(text, radix_or_culture))
        end

        def to_string(value, culture)
          formatted = CNA::Runtime::Numeric.single_round_trip_string(value)
          # The round-trip formatter writes the invariant "." and "-"; a culture with its own
          # spellings gets them here, which is the whole of the culture dependence of a Single.
          formatted = formatted.sub(".", culture.NumberDecimalSeparator) unless culture.NumberDecimalSeparator == "."
          formatted = formatted.sub("-", culture.NegativeSign) unless culture.NegativeSign == "-"
          formatted
        end
      end

      # The Ruby projection of the two `System.ComponentModel.TypeDescriptor` statics the measured
      # XNA behaviour reaches, and nothing else.
      #
      # `TypeDescriptor` is a static utility that nothing inherits, so the inherited-surface rule
      # does not apply to it and the reached-surface rule does: `MathTypeConverter.ConvertToValues`
      # and `ConvertFromValues` call `GetConverter(Type)`, and `ExpandableObjectConverter.GetProperties`
      # calls `GetProperties(object, Attribute[])`. Its other seventy public statics -- the provider,
      # designer, editor, event and extender infrastructure -- are reached by nothing and are
      # deliberately absent.
      #
      # ## The registry is explicit and load-order independent
      #
      # The CLR resolves a converter by reading a `TypeConverterAttribute` off the type. Ruby has no
      # annotations, so a type's converter is **registered**, once, from the file that declares the
      # converter. Nothing scans constants, nothing infers a converter from a naming convention and
      # nothing depends on which file was required first: cold-loading the thirteen converter files
      # in any order produces identical answers, which `test/test_design_converters.rb` asserts by
      # doing exactly that in a subprocess with a shuffled order.
      module TypeDescriptor
        CLR_IDENTITY = "System.ComponentModel.TypeDescriptor"

        # The three entries of `ReflectTypeDescriptionProvider`'s intrinsic table the Design family
        # reaches, keyed by **CLR identity** rather than by Ruby class.
        #
        # Keying by Ruby class is impossible here and the reason is a genuine language mapping
        # limitation rather than a shortcut: Ruby's `Integer` is the projection of both
        # `System.Int32` and `System.Byte`, so `GetConverter(Integer)` cannot answer both
        # `Int32Converter` and `ByteConverter`. The IL never asks it to -- it names the element type
        # explicitly, `ConvertToValues<uint8>` for `ColorConverter` and `<int32>` for
        # `PointConverter` -- and this table resolves on that name, so the converters take exactly
        # the path the CLR takes. `GetConverter` answers the reachable half of the same fact for a
        # Ruby type, and `System.Byte`'s converter is the one an ordinary consumer cannot name.
        INTRINSIC = {
          "System.Int32" => "Int32Converter",
          "System.Single" => "SingleConverter",
          "System.Byte" => "ByteConverter"
        }.freeze

        class << self
          # The element converter for a CLR scalar identity, which is what
          # `MathTypeConverter.ConvertToValues` and `ConvertFromValues` resolve.
          def scalar_converter(clr_identity)
            name = INTRINSIC.fetch(clr_identity) do
              raise ::ArgumentError, "no intrinsic converter is admitted for #{clr_identity}"
            end
            ComponentModel.const_get(name).new
          end

          # Registers the converter type for a projected type. Idempotent: registering the same
          # pair twice is a no-op, and registering a different converter for a type already
          # registered raises rather than silently taking the last writer -- a load order that
          # changed the answer is exactly what this registry exists to prevent.
          def register_converter(type, converter_type)
            existing = converters[type]
            return type if existing.equal?(converter_type)
            raise ::ArgumentError, "#{type} already has converter #{existing}" unless existing.nil?

            converters[type] = converter_type
            type
          end

          # `TypeDescriptor.GetConverter(Type)`. The CLR answers a `TypeConverter` for every type,
          # falling back to the base `TypeConverter` when nothing more specific is registered. This
          # answers a **new instance** each call, as the CLR does for a converter with no cached
          # provider, so a consumer mutating one cannot affect another.
          def GetConverter(type)
            raise ::ArgumentError, "type" if type.nil?

            (converters[type] || intrinsic_for(type) || TypeConverter).new
          end

          # `TypeDescriptor.GetProperties(object)` and `(object, Attribute[])`. A projected type
          # whose members are registered with the reflection registry answers a collection of
          # descriptors over them, in registration order; anything else answers the empty
          # collection, which is what the CLR answers for a type with no browsable properties.
          #
          # `attributes` filters in the CLR. This binding attaches no attributes to a projected
          # member, so a non-empty filter can match nothing and the answer is the empty collection
          # -- measured behaviour rather than an ignored argument.
          def GetProperties(value, attributes = nil)
            return PropertyDescriptorCollection.Empty if value.nil?
            return PropertyDescriptorCollection.Empty unless attributes.nil? || attributes.empty?

            type = value.is_a?(::Module) ? value : value.class
            builder = property_builders[type]
            return PropertyDescriptorCollection.Empty if builder.nil?

            builder.call
          end

          # Registers how a type's descriptors are built. The block is called on each
          # `GetProperties`, so the collection a caller receives is its own and mutating it cannot
          # affect the next caller -- which is what the CLR does for a type whose properties come
          # from reflection rather than from a cached provider.
          def register_properties(type, &builder)
            raise ::ArgumentError, "a block is required" if builder.nil?

            property_builders[type] = builder
            type
          end

          def registered_converter_types = converters.keys
          def converter_registered?(type) = converters.key?(type)

          private

          # The Ruby half of the intrinsic table: `Integer` is what `System.Int32` projects to and
          # `Float` what `System.Single` does, so those two answers are reachable by a consumer
          # holding a Ruby type. `System.Byte` shares `Integer` with `System.Int32` and loses the
          # tie, which is why the element path resolves by CLR identity instead.
          def intrinsic_for(type)
            return Int32Converter if type.equal?(::Integer)
            return SingleConverter if type.equal?(::Float)

            nil
          end

          def converters = @converters ||= {}
          def property_builders = @property_builders ||= {}
        end
      end
    end
  end
end
