# frozen_string_literal: true

module CNA
  module Runtime
    # The four spatial properties AudioListener and AudioEmitter share.
    #
    # Both XNA types keep their state inside a native-layout XACT struct and pass every Vector3
    # through UnsafeNativeStructures::FlipHandedness, which is exactly `(X, Y, -Z)`, on **both** the
    # getter and the setter. Storing the native-handedness value and flipping in both directions is
    # what the pinned IL does, and it is reproduced literally rather than cancelled out, because the
    # cancellation is not quite exact: the constructor stores Position and Velocity **unflipped**,
    # so their first read answers a Z of negative zero, while Forward and Up are flipped at
    # construction and therefore read back as Vector3.Forward and Vector3.Up exactly.
    #
    # Nothing here is native. The XACT struct is only a storage layout; no audio engine exists in
    # this binding, and no value set here reaches one.
    module XactSpatialState
      def Position = flip_handedness(@xact_position)

      def Position=(value)
        @xact_position = flip_handedness(require_vector3(value))
      end

      def Velocity = flip_handedness(@xact_velocity)

      def Velocity=(value)
        @xact_velocity = flip_handedness(require_vector3(value))
      end

      def Forward = flip_handedness(@xact_forward)

      def Forward=(value)
        @xact_forward = flip_handedness(require_vector3(value))
      end

      def Up = flip_handedness(@xact_up)

      def Up=(value)
        @xact_up = flip_handedness(require_vector3(value))
      end

      private

      # The constructor's four stores, in IL order.
      def initialize_xact_spatial_state
        vector3 = Microsoft::Xna::Framework::Vector3
        @xact_position = vector3.Zero
        @xact_velocity = vector3.Zero
        @xact_forward = flip_handedness(vector3.Forward)
        @xact_up = flip_handedness(vector3.Up)
      end

      def flip_handedness(vector)
        Microsoft::Xna::Framework::Vector3.new(vector.X, vector.Y, -vector.Z)
      end

      def require_vector3(value)
        GeometrySupport.require_type(value, Microsoft::Xna::Framework::Vector3)
        value
      end
    end
  end
end

module CNA
  module Runtime
    # Marshals the two XACT spatial value types into the C structures `Apply3D` takes.
    #
    # Both are **snapshots**: `cna_sound_effect_instance_apply_3d` copies what it is given and keeps
    # no reference, so a later mutation of the Ruby listener is not seen by an already-applied
    # instance. That is what the CLR does too -- the parameters are by-value structs -- and it is why
    # nothing here retains the Fiddle buffers beyond the call.
    module Audio
      module_function

      def listener(value)
        raise TypeError, "listener must be an AudioListener" unless value.class.name&.end_with?("AudioListener")

        block = CNA::Native::Layouts::AudioListener.new
        write_vector(block, 8, value.Forward)
        write_vector(block, 20, value.Position)
        write_vector(block, 32, value.Up)
        write_vector(block, 44, value.Velocity)
        block
      end

      def emitter(value)
        block = CNA::Native::Layouts::AudioEmitter.new
        block.write_f32(8, value.DopplerScale)
        write_vector(block, 12, value.Forward)
        write_vector(block, 24, value.Position)
        write_vector(block, 36, value.Up)
        write_vector(block, 48, value.Velocity)
        block
      end

      # `apply_3d_multi_ext` takes a contiguous array of listeners, so the blocks are packed into one
      # buffer rather than passed as an array of pointers.
      def listener_block(values)
        blocks = values.map { |value| listener(value) }
        size = CNA::Native::Layouts::AudioListener.size
        buffer = Fiddle::Pointer.malloc(size * blocks.length, Fiddle::RUBY_FREE)
        blocks.each_with_index { |block, index| buffer[index * size, size] = block.pointer[0, size] }
        buffer
      end

      def write_vector(block, offset, vector)
        block.write_f32(offset, vector.X)
        block.write_f32(offset + 4, vector.Y)
        block.write_f32(offset + 8, vector.Z)
      end
    end
  end
end
