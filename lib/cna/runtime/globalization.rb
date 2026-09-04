# frozen_string_literal: true

module CNA
  module Runtime
    # The Ruby projection of `System.Globalization.CultureInfo` and `System.Globalization.TextInfo`.
    #
    # These are **BCL language projections**, not XNA types. They live in the CNA runtime rather
    # than a fabricated Ruby `::System` namespace, exactly as `EventArgs`, `Attribute` and
    # `ReadOnlyCollection` do, and no method they declare is an XNA identity.
    #
    # ## Why they are here
    #
    # `CultureInfo` is the second parameter of every XNA `Design` `ConvertFrom` and `ConvertTo` --
    # twenty-one public members across the thirteen converters -- so it is **directly** demanded.
    # `TextInfo` is demanded transitively through it, the way `SeekOrigin` is through `Stream::Seek`:
    # no XNA signature names it, `CultureInfo.TextInfo` does, and its `ListSeparator` is the string
    # the whole converter family splits and joins on. `MathTypeConverter.ConvertToValues` calls
    # `culture.TextInfo.ListSeparator` at `IL_002b`/`IL_0030` and `ConvertFromValues` at
    # `IL_000b`/`IL_0010`, both after resolving a nil culture to `CurrentCulture`.
    #
    # ## What this binding does not have, and says so
    #
    # The CLR reads a culture's data from the operating system's locale tables. Ruby has no
    # equivalent, and this binding will not invent one: shipping a locale database would be
    # asserting facts about hundreds of cultures that nothing here measured. So a `CultureInfo` is
    # the four strings the admitted reach actually consumes, plus its name, and a consumer that
    # wants a culture other than the invariant one **constructs it with those values**. That is a
    # recorded `LANGUAGE_MAPPING_LIMITATION` on the CLR type, not a silent one:
    # `CultureInfo.GetCultures`, calendars, casing tables, date formats and the sixty-odd other
    # public members of the CLR class are deliberately absent, because none of them is reachable
    # from the admitted surface and none could be answered honestly.
    #
    # ## The invariant culture is measured, not remembered
    #
    # Every value below is read out of the pinned mscorlib's `System.Globalization.CultureData`
    # invariant initialiser, where each is a literal `ldstr` followed by the `stfld` that stores it:
    #
    #     sName = ""            sListSeparator = ","      sDecimalSeparator = "."
    #     sThousandSeparator = ","                        sNegativeSign = "-"
    #     sPositiveSign = "+"   sNaN = "NaN"              sPositiveInfinity = "Infinity"
    #     sNegativeInfinity = "-Infinity"
    #
    # `CurrentCulture` answers the invariant culture unless a consumer sets one. The CLR takes it
    # from the thread; a Ruby process has no CLR thread culture, and defaulting to the invariant one
    # is the only answer this binding can make that is the same on every machine. Determinism is the
    # point: a converter's output must not depend on the host's locale environment.
    module Globalization
      # The Ruby projection of `System.Globalization.TextInfo`.
      #
      # The CLR class carries casing tables, code pages and the ANSI/OEM/Mac code page identifiers.
      # None of that is reachable from the admitted surface: `ListSeparator` is the one member the
      # converter family reads, and `CultureName`/`ToString` are what identify the instance. A
      # consumer never constructs one -- it is answered by `CultureInfo#TextInfo` -- so `new` is
      # private, the same decision `Stream` records for a class with no public CLR constructor.
      class TextInfo
        CLR_IDENTITY = "System.Globalization.TextInfo"

        attr_reader :ListSeparator, :CultureName

        def initialize(culture_name, list_separator)
          @CultureName = culture_name.dup.freeze
          @ListSeparator = list_separator.dup.freeze
          freeze
        end

        private_class_method :new

        # Constructed only by CultureInfo, which is the only thing that knows a culture's data.
        # A private class method is still callable with an implicit receiver from inside the class.
        def self.for_culture(culture_name, list_separator) = new(culture_name, list_separator)

        def ToString = "TextInfo - #{@CultureName}"
        alias to_s ToString
      end

      # The Ruby projection of `System.Globalization.CultureInfo`.
      class CultureInfo
        CLR_IDENTITY = "System.Globalization.CultureInfo"

        # The invariant culture's data, every value read out of the pinned mscorlib rather than
        # remembered. `CultureData`'s invariant initialiser stores each of these as a literal.
        INVARIANT_DATA = {
          name: "",
          listSeparator: ",",
          numberDecimalSeparator: ".",
          numberGroupSeparator: ",",
          negativeSign: "-",
          positiveSign: "+",
          nanSymbol: "NaN",
          positiveInfinitySymbol: "Infinity",
          negativeInfinitySymbol: "-Infinity"
        }.freeze

        attr_reader :Name, :NumberDecimalSeparator, :NumberGroupSeparator, :NegativeSign,
                    :PositiveSign, :NaNSymbol, :PositiveInfinitySymbol, :NegativeInfinitySymbol

        # A culture is its name plus the separators the admitted reach consumes. Anything not given
        # falls back to the invariant value, so constructing `CultureInfo.new("de-DE",
        # listSeparator: ";", numberDecimalSeparator: ",")` is enough to exercise every
        # culture-dependent path in the converter family without inventing a locale database.
        def initialize(name, listSeparator: nil, numberDecimalSeparator: nil,
                       numberGroupSeparator: nil, negativeSign: nil, positiveSign: nil,
                       nanSymbol: nil, positiveInfinitySymbol: nil, negativeInfinitySymbol: nil)
          raise ::ArgumentError, "name" if name.nil?

          @Name = String(name).dup.freeze
          @list_separator = (listSeparator || INVARIANT_DATA.fetch(:listSeparator)).dup.freeze
          @NumberDecimalSeparator = (numberDecimalSeparator || INVARIANT_DATA.fetch(:numberDecimalSeparator)).dup.freeze
          @NumberGroupSeparator = (numberGroupSeparator || INVARIANT_DATA.fetch(:numberGroupSeparator)).dup.freeze
          @NegativeSign = (negativeSign || INVARIANT_DATA.fetch(:negativeSign)).dup.freeze
          @PositiveSign = (positiveSign || INVARIANT_DATA.fetch(:positiveSign)).dup.freeze
          @NaNSymbol = (nanSymbol || INVARIANT_DATA.fetch(:nanSymbol)).dup.freeze
          @PositiveInfinitySymbol = (positiveInfinitySymbol || INVARIANT_DATA.fetch(:positiveInfinitySymbol)).dup.freeze
          @NegativeInfinitySymbol = (negativeInfinitySymbol || INVARIANT_DATA.fetch(:negativeInfinitySymbol)).dup.freeze
          @TextInfo = TextInfo.for_culture(@Name, @list_separator)
          freeze
        end

        # `CultureInfo.TextInfo` is a property, and the CLR answers the same instance every time for
        # a given culture. Building one per read would make `culture.TextInfo.equal?(culture.TextInfo)`
        # false where the CLR makes it true, so it is built once in the constructor.
        attr_reader :TextInfo

        # `CultureInfo.InvariantCulture` -- a single shared instance, as the CLR's `initonly` static
        # field is -- and `CultureInfo.CurrentCulture`. The CLR reads the current one from the
        # thread; this binding has no CLR thread, so the invariant culture is the answer until a
        # consumer sets one. Deliberately settable, because `MathTypeConverter` resolves a nil
        # `culture` argument through it and a consumer testing culture-dependent behaviour needs to
        # be able to say what "current" means.
        class << self
          # A capitalised method name is a constant reference when written bare, so every internal
          # call below carries an explicit `self.`.
          def InvariantCulture
            @InvariantCulture ||= new(INVARIANT_DATA.fetch(:name))
          end

          def CurrentCulture = @CurrentCulture || self.InvariantCulture

          def CurrentCulture=(culture)
            unless culture.nil? || culture.is_a?(CultureInfo)
              raise TypeError, "CurrentCulture takes a CNA::Runtime::Globalization::CultureInfo or nil"
            end

            @CurrentCulture = culture
          end

          # Sets `CurrentCulture` for the duration of the block and restores whatever was there
          # before, including nil. A test that changed a process-wide value and left it changed
          # would leak into every later test, so the block form is the supported way to do it.
          def with_current_culture(culture)
            previous = @CurrentCulture
            self.CurrentCulture = culture
            yield
          ensure
            @CurrentCulture = previous
          end
        end

        # Two cultures are the same culture when they carry the same data. The CLR compares by
        # culture identity; this binding has no LCID, so the data it does carry is the identity.
        def ==(other)
          other.is_a?(CultureInfo) && other.Name == @Name && other.TextInfo.ListSeparator == @TextInfo.ListSeparator &&
            other.NumberDecimalSeparator == @NumberDecimalSeparator &&
            other.NumberGroupSeparator == @NumberGroupSeparator &&
            other.NegativeSign == @NegativeSign
        end
        alias eql? ==

        def hash = [@Name, @TextInfo.ListSeparator, @NumberDecimalSeparator, @NumberGroupSeparator, @NegativeSign].hash

        def ToString = @Name
        alias to_s ToString
      end
    end
  end
end
