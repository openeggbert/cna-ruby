# frozen_string_literal: true

require_relative "numeric"

module CNA
  module Runtime
    # The shape XNA's four graphics state objects share, derived from the pinned
    # Microsoft.Xna.Framework.Graphics.dll IL (SHA-256 560080fc…).
    #
    # `BlendState`, `DepthStencilState`, `RasterizerState` and `SamplerState` are the same type
    # written four times. Each is a `GraphicsResource` subclass whose public surface is a
    # constructor, an inherited `Dispose`, a set of properties and a set of static presets, and each
    # is built the same way:
    #
    #     .ctor()                  { Object::.ctor(); SetDefaults(); isBound = false; }
    #     .ctor(…, string name)    { Object::.ctor(); SetDefaults(); …; Name = name; isBound = true; }
    #     get_X()                  { return cachedX; }                      // one ldfld
    #     set_X(value)             { ThrowIfBound(); cachedX = value; }      // no validation at all
    #     ThrowIfBound()           { if (isBound) throw new InvalidOperationException(
    #                                  Format(FrameworkResources.BoundStateObject, GetType().Name)); }
    #
    # Every setter is that one shape, which is why this module generates them rather than writing
    # sixty-five near-identical pairs; `test_graphics_state_objects.rb` asserts the shape holds for
    # every property of all four types rather than trusting the generator.
    #
    # This module lives in `CNA::Runtime` and not in the XNA namespace on purpose: a helper module
    # inside `Microsoft::Xna::Framework` is an `INTERNAL_TYPE_LEAK`, which the API verifier measures.
    module GraphicsState
      # `FrameworkResources.BoundStateObject` is a localized resource string this binding does not
      # ship; what is reproduced is the exception **type** and the fact that the type's own name is
      # what the message names, which is the part a consumer can act on.
      def throw_if_bound!
        return unless @is_bound

        raise ::RuntimeError,
              "#{self.class.name.split("::").last} is bound to a graphics device and cannot be changed"
      end

      # The preset constructor's tail: `Name = name; isBound = true`. XNA's own presets are the only
      # instances that are bound at construction, and on this artifact they are the only bound ones
      # that exist at all -- `Apply` is `assembly`-visible, is not a projected identity, and nothing
      # else sets the flag.
      #
      # `Name` is assigned **before** the flag, which is the IL's order and is why it is settable at
      # all: `GraphicsResource::set_Name` carries no bound check, so a bound state can still be
      # renamed afterwards, exactly as in XNA. The object is deliberately not `freeze`d either: a
      # frozen Ruby object would refuse the inherited mutable members too -- `Tag`, and disposal --
      # which XNA's bound state objects still accept.
      def bind_as_preset!(name)
        self.Name = name
        @is_bound = true
        nil
      end

      def self.included(base) = base.extend(ClassMethods)

      module ClassMethods
        # One XNA property: a getter that is one field read, and a setter that checks the bound flag
        # and stores. `kind` is how the value is admitted, which is this binding's typing rather
        # than XNA's -- the IL validates nothing here, so an undeclared enum value or a non-Integer
        # is refused by the projection instead of being stored.
        def state_property(name, kind)
          field = :"@#{name}"

          define_method(name) do
            value = instance_variable_get(field)
            value.is_a?(CNA::Runtime::ValueSemantics) ? value.dup : value
          end

          define_method(:"#{name}=") do |value|
            throw_if_bound!
            instance_variable_set(field, GraphicsState.admit(value, kind, name.to_s))
            value
          end
        end
      end

      # The admission rules, one per property kind actually used by the four types.
      def self.admit(value, kind, name)
        case kind
        when :int32 then Numeric.int32(value, name)
        when :single then Numeric.f32(value)
        when :boolean
          raise ::TypeError, name unless value == true || value == false

          value
        else
          raise ::TypeError, name unless value.instance_of?(kind)

          value.is_a?(ValueSemantics) ? value.dup : value
        end
      end
    end
  end
end
