# frozen_string_literal: true

module CNA
  module Runtime
    # The non-XNA CLR identities this binding projects, and what each one projects to.
    #
    # This register is measured, not aspirational: the API verifier resolves every entry and
    # reports a mapping mismatch for any that does not exist or does not have the declared shape,
    # and the dependency frontier consumes the same register. A BCL type can therefore never be
    # reported as mapped unless the runtime really projects it.
    #
    # It stays deliberately narrow. Only a CLR identity the selected XNA surface actually names, and
    # whose Ruby projection can be decided without guessing, belongs here.
    # The Ruby projection of System.Attribute: a marker base with no members of its own.
    class Attribute
    end

    module BclProjection
      # CLR type identity => Ruby constant path.
      #
      # System.EventArgs is the argument half of System.EventHandler`1, projected by Foundation 20
      # as CNA::Runtime::EventArgs. It lives in the CNA runtime rather than a fabricated Ruby
      # ::System namespace, which is the rule mapping-rules.json already applies elsewhere.
      # System.TimeSpan projects to an ordinary Ruby Float carrying seconds. GameTime has projected
      # it that way since Foundation 1; Foundation 23 makes the rule measured rather than implicit,
      # because GestureSample.Timestamp is the second consumer. A TimeSpan is a tick count and a
      # binary64 Float is not, so the projection is exact only within Float's 53-bit significand —
      # documented as a LANGUAGE_MAPPING_LIMITATION, not hidden.
      # System.Attribute projects to CNA::Runtime::Attribute, an empty marker base. Ruby has no
      # annotation mechanism, so a CLR attribute projects as an ordinary data-carrying class; what
      # the base preserves is the CLR base identity, which the API verifier measures. None of the
      # XNA attribute types declares a member inherited from System.Attribute, so the base declares
      # none either.
      # System.Collections.ObjectModel.ReadOnlyCollection`1 projects to
      # CNA::Runtime::ReadOnlyCollection, a dedicated runtime support class rather than an Array, a
      # frozen Array, Enumerable alone, a Set or an opaque Object. Foundation 28 admitted a
      # Microsoft mscorlib as a separate BCL authority precisely so this one could be measured
      # instead of guessed: the CLR type is a live *view* over the IList<T> it is constructed with,
      # it validates nothing of its own, and it refuses mutation by implementing every mutating
      # interface member as an unconditional throw. A frozen Ruby Array would get the view semantics
      # wrong; a plain Array would get the refusal wrong. Ruby has class inheritance, so an XNA
      # class whose actual BCL base is this generic inherits from the support class and the CLR base
      # relationship survives.
      # System.Collections.ObjectModel.Collection`1 projects to CNA::Runtime::Collection, the
      # mutable sibling of that class and the same measurement applied to the opposite intent. The
      # mscorlib IL shows the two are one shape: both store a single IList<T> field, both forward
      # every read to it and neither copies anything. What differs is that this one's mutating
      # members are ordinary public members, and every one of them routes through a protected
      # virtual hook -- InsertItem, RemoveItem, SetItem, ClearItems -- rather than touching the
      # backing list. That indirection is the type, so the projection declares no Ruby-idiomatic
      # mutation beside it: a `<<` or a `push` would be a second way to mutate that a subclass's
      # hook never sees. A bare Array gets that wrong, and a frozen Array gets the view wrong.
      # System.Collections.Generic.Dictionary`2 projects to CNA::Runtime::Dictionary, the third
      # member of the same family and the same measurement applied to a keyed store. One XNA type
      # takes it as a base -- LaunchParameters, a Dictionary<string, string> -- so the CLR base
      # relationship has to survive, and Ruby class inheritance is what carries it. The pinned
      # mscorlib settles how much of the type a projection actually owes: twenty-two of its methods
      # are explicit interface implementations, which project to nothing under the rule
      # ReadOnlyCollection's twelve and Collection's fourteen already follow, and its
      # SerializationInfo constructor is `family`. What is left is one ordinary public surface --
      # Comparer, Count, Keys, Values, the indexer, Add, Clear, ContainsKey, ContainsValue,
      # GetEnumerator, Remove, TryGetValue, GetObjectData and OnDeserialization -- and that is what
      # the support class carries. A Ruby Hash is its private store and never its public projection:
      # Hash#[] answers nil where get_Item throws, Hash#store overwrites where Add throws, and
      # Hash#each never fails fast on a version counter.
      # System.Runtime.Serialization.SerializationInfo and StreamingContext are the parameter types
      # of the `family .ctor(SerializationInfo, StreamingContext)` that two XNA exception types --
      # Content.ContentLoadException and Storage.StorageDeviceNotConnectedException -- declare
      # alongside the standard trio. Both were deferred for eight milestones as "a BCL cluster no
      # otherwise-unblocked type needs".
      #
      # They are projected as classes rather than collapsed, and the reason is a Ruby fact rather
      # than a preference: those types have *two* two-argument constructors, `(message,
      # innerException)` and `(info, context)`, and Ruby has no overload by parameter type, so one
      # `initialize` must tell them apart. A nominal first argument makes that a decision; a marker
      # or a duck type would make it a guess.
      #
      # The XNA surface names both and calls no member of either -- every one of those constructors
      # is a pure forward to System.Exception's -- so the narrowness rule applies exactly as it does
      # to System.Type: each projects to what that surface can reach. SerializationInfo carries the
      # general AddValue/GetValue pair and MemberCount; mscorlib's other forty public members are
      # the typed overloads a dynamically typed language has nothing to distinguish, plus a
      # formatter's type-resolution protocol no formatter here runs. StreamingContext is the value
      # type it is in the IL, two fields with value equality. StreamingContextStates is deliberately
      # *not* registered: the selected reference never names it, and the register admits only
      # identities that surface really names.
      # System.IO.Stream projects to CNA::Runtime::Stream, one Ruby class for the whole family. The
      # CLR type is abstract and the selected XNA surface never names a concrete stream --
      # TitleContainer hands back a FileStream, StorageContainer something else, and a caller sees
      # `Stream` either way -- so where the bytes live is a private backing rather than a second
      # projected identity, and `new` is private for the same reason Foundation 25 made it private
      # for a class with no public constructor. Seventeen XNA members reach System.IO, in both
      # directions: OpenStream, OpenFile/CreateFile and four Media getters produce one, while
      # SoundEffect.FromStream, both Texture2D.FromStream overloads, SaveAsPng/SaveAsJpeg and
      # MediaLibrary.SavePicture consume one, so a produce-only projection would not have been
      # enough. The projected surface is the reached surface: the four Begin/End asynchronous
      # members, Synchronized and the Null field are measured and deliberately absent, each because
      # projecting it would mean inventing a type the inventory does not carry. Full derivation in
      # docs/stream-projection-design.md.
      #
      # System.IO.SeekOrigin projects to CNA::Runtime::Stream::SeekOrigin. It is the first
      # transitively demanded BCL identity: no XNA signature names it, System.IO.Stream::Seek does,
      # and a consumer holding a stream this binding produced needs it to seek at all. Its three
      # values are read out of the pinned mscorlib -- Begin=0, Current=1, End=2 -- not remembered.
      TYPES = {
        "System.EventArgs" => "CNA::Runtime::EventArgs",
        # System.Byte[] projects to a Ruby String in Encoding::BINARY -- Ruby's own byte buffer,
        # mutable in place, whose `bytesize` is the CLR `Length`, and already what every native
        # boundary in this binding produces and consumes. An Array of Integers would need a
        # conversion at each of those boundaries and its `length` would equal the byte count only by
        # coincidence of the element type. The two properties a CLR array has and a Ruby String does
        # not -- it cannot be resized and is never frozen -- are guarded at each boundary rather than
        # ignored; `CNA::Runtime::Stream#Read` refuses both. Reach was measured before the decision:
        # eight XNA signatures over five public members, plus `Stream.Read`/`Write` through a
        # produced stream. Full derivation in docs/stream-projection-design.md.
        "System.Byte[]" => "String",
        "System.IO.Stream" => "CNA::Runtime::Stream",
        "System.IO.SeekOrigin" => "CNA::Runtime::Stream::SeekOrigin",
        # The three enums `StorageContainer.OpenFile`'s overloads name. Transitively demanded the
        # way `SeekOrigin` was -- no XNA type of this binding's own declares one -- and every value
        # read out of the pinned mscorlib: `FileMode` is 1..6 with **no zero**, `FileAccess` and
        # `FileShare` are `[Flags]`. CNA's `CNA_FILE_*` identities were read out of `storage.h`
        # independently and are numerically the same, which the ABI gate checks as fifteen constants.
        "System.IO.FileMode" => "CNA::Runtime::Stream::FileMode",
        "System.IO.FileAccess" => "CNA::Runtime::Stream::FileAccess",
        "System.IO.FileShare" => "CNA::Runtime::Stream::FileShare",
        # `System.IAsyncResult` is named by four XNA signatures, every one of them a Storage
        # `BeginXxx` return or an `EndXxx` argument. XNA's own two implementations of it are
        # `private` and neither is asynchronous: the wait handle is created **already signalled**,
        # `CompletedSynchronously` is `ldc.i4.1`, and `BeginShowSelector` invokes the callback
        # inline before returning. So the projection is a completed result, which is the shape the
        # contract actually has. `CNA::Runtime::AsyncResult` carries the derivation.
        "System.IAsyncResult" => "CNA::Runtime::AsyncResult",
        # `System.Threading.WaitHandle` is reachable through exactly one member of one property --
        # `IAsyncResult.AsyncWaitHandle.WaitOne`, on a handle that is permanently signalled -- so
        # the projection carries that one member and its two overloads and nothing else. No
        # `ManualResetEvent`, `Set`, `Reset` or `SafeHandle` is invented: the reachable surface
        # cannot call them.
        "System.Threading.WaitHandle" => "CNA::Runtime::AsyncResult::WaitHandle",
        "System.Collections.Generic.Dictionary`2" => "CNA::Runtime::Dictionary",
        "System.Runtime.Serialization.SerializationInfo" => "CNA::Runtime::SerializationInfo",
        "System.Runtime.Serialization.StreamingContext" => "CNA::Runtime::StreamingContext",
        "System.TimeSpan" => "Float",
        "System.Attribute" => "CNA::Runtime::Attribute",
        "System.Collections.ObjectModel.ReadOnlyCollection`1" => "CNA::Runtime::ReadOnlyCollection",
        "System.Collections.ObjectModel.Collection`1" => "CNA::Runtime::Collection",
        # `IList`1` is named once in the selected surface, by
        # `Media.MediaSource.GetAvailableMediaSources`, and what the IL actually returns there is a
        # plain `MediaSource[]` -- `ldc.i4.1; newarr; stelem.ref; ret`. A CLR array is indexable and
        # fixed-length, which is what a Ruby Array is; the mutable-view contract `IList<T>` carries
        # in general is not exercised, because the only producer hands back an array it just built
        # and keeps no reference to it. `Keys[]` from `KeyboardState.GetPressedKeys` set the same
        # precedent for a CLR array before this register named it.
        "System.Collections.Generic.IList`1" => "Array",
        # `System.Char` is a **UTF-16 code unit**, not a character: the pinned mscorlib declares it
        # as a 16-bit value type, and `0xD800` is a perfectly valid one. Ruby has no character type,
        # and the two candidates differ in exactly that place. A one-character Ruby String is a code
        # *point* in some encoding, so it cannot hold an unpaired surrogate and would force an
        # encoding decision the CLR type does not have; an Integer holds the code unit exactly. The
        # register's rule is to project what the XNA surface can reach, and the surface --
        # `SpriteFont.Characters`, `DefaultCharacter`, and the content pipeline's `CharReader` --
        # can reach any code unit. So `Integer`, and a consumer writes `"*".ord` rather than `"*"`.
        # `System.Byte[] => String` was decided the same way and lands the other side of the same
        # line: a `byte[]` really is a byte sequence, and a Ruby String really is one.
        "System.Char" => "Integer",
        # A CLR `Nullable<T>` is "the value, or nothing", which Ruby spells `nil`. There is no
        # wrapper to project: `HasValue` is `!nil?` and `Value` is the object itself. The one place
        # the selected surface names it is `SpriteFont.DefaultCharacter`.
        "System.Nullable`1" => "NilClass",
        # `System.Text.StringBuilder` is a **mutable** string, and a Ruby String is one. The selected
        # surface names it once, in the second `MeasureString` overload, and Ruby collapses the two
        # overloads into one method taking a String -- which is what the no-overloading rule would
        # produce from this mapping anyway.
        "System.Text.StringBuilder" => "String",
        # System.Type is a *type token* everywhere the selected XNA surface names it -- a service
        # key, a content reader's target type, an index element type, a converter's destination --
        # in all twenty-four places. Ruby's type token is a Module, and a Class is one. The single
        # operation any of those members performs on it, IsAssignableFrom(value.GetType()), is
        # exactly `value.is_a?(type)`, and a Module used as a Hash key compares by identity, which
        # is what Dictionary<Type, ...>'s default comparer does. Nothing here claims the CLR Type
        # reflection surface; the register records what the XNA surface actually uses.
        "System.Type" => "Module"
      }.freeze

      # A BCL identity the selected XNA surface names that projects to **no Ruby constant at all**,
      # and the measured reason.
      #
      # Ruby has no interfaces. A BCL interface whose whole declared surface the implementing XNA
      # type already exposes publicly therefore survives as those members, and inventing a Ruby
      # module for it would add an identity the CLR contract does not have and that nothing could
      # measure. This is the same collapse ExternalException takes, applied to a shape that has no
      # ancestor to collapse *to*: the entry is recorded rather than left silent so the dependency
      # frontier can count the identity as decided, and so the API verifier can assert that no
      # constant was invented after all.
      STRUCTURAL_COLLAPSE = {
        "System.Resources.ResourceManager" => "the one type that names it, Content.ResourceContentManager, reaches exactly one of its members: `GetObject(string)`, whose answer it immediately tests for null and then for `byte[]`. A .NET resource set is a satellite assembly's embedded `.resources` blob, which a Ruby program does not have and this binding will not invent; what the XNA surface can reach is a lookup from a name to bytes, so the contract survives as any object answering `GetObject`, the same collapse `System.Action`1` records for a callable, and no Ruby constant is invented",
        "System.IServiceProvider" => "declares one member, GetService(Type), which GameServiceContainer declares publicly; the contract survives as that member and no Ruby constant is invented",
        # The admitted mscorlib says `System.IDisposable` declares exactly one member --
        # `void Dispose()` -- and nothing else. No Close, no IsDisposed, no finalizer contract, no
        # ownership protocol: those are conventions built on top of it, not part of it. Twenty-nine
        # XNA types declare it; twenty-eight declare a public parameterless Dispose() of their own,
        # and the twenty-ninth, GraphicsDeviceManager, implements it as an explicit interface
        # implementation, which projects to no member at all under the rule ReadOnlyCollection's
        # twelve and Collection's fourteen already follow. So the contract survives as the members
        # the implementing types already declare, and inventing a Ruby module -- or a Close alias,
        # or a finalizer API, or an ownership wrapper -- would add identities the CLR contract does
        # not have and that nothing could measure. Mapping the identity says nothing whatever about
        # whether a given type's disposal is implemented: that stays each type's own measured work.
        "System.IDisposable" => "declares one member, Dispose(), which every implementing XNA type either declares publicly or implements explicitly; the contract survives as those members and no Ruby constant, Close alias, finalizer API or ownership wrapper is invented",
        # `System.Action`1` declares one member, `Invoke(T)`, and Ruby's universal callable protocol
        # is `#call`. A `Proc`, a lambda, a `Method` and any object defining `call` are all callable,
        # so mapping the identity to `Proc` would reject three of the four for no measured reason,
        # and inventing a `CNA::Runtime::Action` wrapper would add an identity the CLR contract does
        # not have -- the same reasoning `IServiceProvider` and `IDisposable` already take.
        #
        # What makes the collapse safe here rather than merely convenient is that the *whole* XNA
        # reach was measured before it was made. `Action`1` appears in exactly two public
        # signatures, `ContentManager.ReadAsset<T>` and `ContentReader.ReadSharedResource<T>`, and
        # the pinned IL shows every use is the same three operations: null-check, store, and
        # `Invoke` once with one argument for a void return. `Delegate.Combine` and
        # `Delegate.Remove` appear nowhere near it, no member exposes one as a property, and none is
        # ever compared. So there is no delegate identity to preserve -- no multicast list, no
        # removal semantics, no equality -- and a callable is the whole of it.
        #
        # `ContentReader.InvokeReader<T>` settles what the parameter *means*, which no signature
        # says: `if (recordDisposableObject != null) recordDisposableObject.Invoke(d); else
        # contentManager.RecordDisposableObject(d);`. It is an override for where a loaded
        # disposable is registered, not an extra notification, so a supplied callable *replaces* the
        # manager's own bookkeeping rather than adding to it.
        "System.Action`1" => "declares one member, Invoke(T), which is Ruby's `#call`; every use across the whole measured XNA reach is null-check, store and one invocation, so there is no delegate identity -- no multicast, removal or equality -- to preserve, and no Ruby constant, Proc restriction or Action wrapper is invented",
        "System.AsyncCallback" => "declares one member, Invoke(IAsyncResult), and the same collapse System.Action`1 records applies for the same reason: Storage's four Begin overloads null-check it and invoke it once, inline, before returning. Any Ruby callable is accepted and no delegate identity is preserved"
      }.freeze

      # A CLR **generic parameter** placeholder: `!!0` for a generic method's, `!0` for a generic
      # type's, either optionally as an array. It is a language construct rather than a type
      # identity, so it must never be counted as an unmapped BCL type -- what resolves it is the
      # generic-method projection rule in `tools/api_compat/mapping-rules.json`, not a register
      # entry. Ruby has no static generics and cannot infer a type argument from a call site, so a
      # CLR generic method projects to a Ruby method taking its type arguments as leading
      # positional parameters, in declaration order, ahead of the CLR value parameters; the type
      # argument is a Ruby `Module`, which is what `System.Type` already projects to.
      GENERIC_PARAMETER = /\A!!?\d+(\[\])*\z/.freeze

      def self.generic_parameter?(signature) = GENERIC_PARAMETER.match?(signature.to_s)

      # CLR exception base identity => the Ruby exception class an XNA type deriving from it takes
      # as its Ruby superclass.
      #
      # An XNA exception must behave as a Ruby exception rather than an ordinary Object subclass.
      # StandardError is the root because a CLR `catch (Exception)` is the analogue of a bare Ruby
      # `rescue`, which catches StandardError and deliberately not ::Exception; mapping to
      # ::Exception would put XNA failures alongside Ruby's non-recoverable system-level conditions
      # and make a bare rescue miss them.
      #
      # Only the two bases the pinned reference actually names appear here: System.Exception (five
      # XNA types) and System.Runtime.InteropServices.ExternalException (three). The selected XNA
      # surface never names ExternalException itself, so no Ruby constant is invented for it; an
      # intermediate BCL exception class collapses to the nearest projected ancestor. That is a
      # deliberate, documented loss of one CLR inheritance level, not an oversight.
      EXCEPTION_BASES = {
        "System.Exception" => "StandardError",
        "System.Runtime.InteropServices.ExternalException" => "StandardError"
      }.freeze

      # A CLR exception a projected member *throws*, and the Ruby exception it raises instead.
      #
      # This is a different register from EXCEPTION_BASES, and the difference is load-bearing. An
      # entry there is a CLR base an XNA exception type *derives from*, so it is named by the
      # reference contract's public signatures. An entry here is never named by a signature at all:
      # it appears only inside a member's IL, as an `ldstr` naming a parameter followed by a
      # `newobj`, or as a call into a throw helper. Mixing the two would let a thrown exception be
      # counted as a mapped BCL identity the XNA surface names, which it is not.
      #
      # One CLR exception maps to exactly one Ruby exception. Every entry must be a real class, must
      # descend from StandardError so a bare `rescue` catches it as a CLR `catch (Exception)` would,
      # and must not descend from ScriptError; the API verifier enforces all three.
      THROWN_EXCEPTIONS = {
        "System.ArgumentNullException" => "ArgumentError",
        "System.ArgumentOutOfRangeException" => "RangeError",
        "System.ArgumentException" => "ArgumentError",
        "System.IndexOutOfRangeException" => "IndexError",
        "System.NotSupportedException" => "CNA::Runtime::NotSupportedError",
        # RuntimeError is Ruby's generic recoverable failure, the class `raise "message"` produces,
        # and InvalidOperationException is the CLR's generic wrong-state failure. This binding was
        # already pairing them before the register existed -- CurveKeyCollection raises RuntimeError
        # for the fail-fast enumeration the CLR signals with InvalidOperationException, and
        # ReadOnlyCollection follows it -- so Foundation 32 makes the pairing measured rather than
        # implicit. FrozenError would say something about frozen objects the CLR does not, and
        # StandardError itself would lose the identity.
        "System.InvalidOperationException" => "RuntimeError",
        # KeyNotFoundException is what Dictionary`2::get_Item throws through
        # ThrowHelper::ThrowKeyNotFoundException when FindEntry answers a negative index. Ruby's
        # KeyError is precisely "the key was not found in this keyed collection", it descends from
        # IndexError and so from StandardError, and it is what Hash#fetch already raises -- so the
        # projection reuses Ruby's own identity rather than inventing one. IndexError itself would
        # lose the distinction the CLR draws between an index and a key, which
        # IndexOutOfRangeException already occupies in this register.
        "System.Collections.Generic.KeyNotFoundException" => "KeyError",
        # SerializationException is what SerializationInfo really throws --
        # Serialization_SameNameTwice from AddValue and Serialization_NotFound from GetElement. A
        # dedicated StandardError subclass for the same reason NotSupportedError is one: it is a
        # distinct CLR identity a caller can rescue by name, and no existing Ruby class says what it
        # says. RuntimeError is already spoken for by InvalidOperationException and would lose the
        # identity; KeyError would claim a keyed collection this is not.
        "System.Runtime.Serialization.SerializationException" => "CNA::Runtime::SerializationError"
      }.freeze

      module_function

      # A structurally collapsed identity deliberately answers nil: there is no Ruby type to name.
      def ruby_type(clr_identity)
        TYPES[clr_identity] || EXCEPTION_BASES[clr_identity] ||
          TYPES[definition(clr_identity)] || EXCEPTION_BASES[definition(clr_identity)]
      end

      # A constructed generic hides its definition behind its type arguments: the reference contract
      # spells the base of ModelBoneCollection as `ReadOnlyCollection`1[...ModelBone]`, and what the
      # register maps is the definition. Reducing to it here is what lets one register entry answer
      # for every closed form, and it is the same reduction the dependency frontier applies.
      def definition(clr_identity) = clr_identity.to_s.sub(/\[.*\]\z/, "")

      # The CLR type arguments of a constructed generic, split at the top level so a nested
      # constructed argument stays whole.
      def element_types(clr_identity)
        arguments = clr_identity.to_s[/\A[^\[]*\[(.*)\]\z/m, 1]
        return [] if arguments.nil?

        parts = []
        depth = 0
        buffer = +""
        arguments.each_char do |char|
          depth += 1 if char == "["
          depth -= 1 if char == "]"
          if char == "," && depth.zero?
            parts << buffer
            buffer = +""
          else
            buffer << char
          end
        end
        parts << buffer
        parts.map(&:strip).reject(&:empty?)
      end

      # A projected identity whose Ruby class carries its CLR type arguments as metadata, because a
      # Ruby class is not statically generic.
      def generic_projection?(clr_identity) = TYPES.key?(definition(clr_identity)) && definition(clr_identity).include?("`")

      def exception_base?(clr_identity) = EXCEPTION_BASES.key?(clr_identity)

      def identities = (TYPES.keys + EXCEPTION_BASES.keys + STRUCTURAL_COLLAPSE.keys).uniq.sort

      def structural_collapse?(clr_identity) = STRUCTURAL_COLLAPSE.key?(clr_identity)

      # Deliberately not part of `identities`: a thrown exception is not an identity the XNA public
      # surface names, so it must never count as a mapped BCL type on the dependency frontier.
      def thrown_identities = THROWN_EXCEPTIONS.keys.sort

      def thrown_exception(clr_identity) = THROWN_EXCEPTIONS[clr_identity]

      # The one validation the TimeSpan projection performs: seconds must be numeric.
      def time_span(value)
        raise TypeError, "TimeSpan maps to numeric seconds" unless value.is_a?(::Numeric)

        Float(value)
      end
    end
  end
end
