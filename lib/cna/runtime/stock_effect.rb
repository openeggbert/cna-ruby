# frozen_string_literal: true

require "fiddle"

module CNA
  module Runtime
    # The shared plumbing behind the five stock effects.
    #
    # It lives here rather than in `Microsoft::Xna::Framework::Graphics` for a structural reason:
    # the strict verifier walks that namespace and reports every `Module` in it that is not a
    # selected XNA type as an `INTERNAL_TYPE_LEAK`. A helper is not an XNA identity, so it does not
    # live where XNA identities do.
    #
    # ## Why the stock effects go through typed routes at all
    #
    # XNA's stock effects are `Effect` subclasses whose properties write into `EffectParameter`s
    # that the built-in compiled shader declares. CNA's are **native objects with typed accessors**:
    # `cna_effect_get_parameters` on an effect from `cna_basic_effect_create` answers a collection
    # of **zero**, measured on the `HEADLESS` and the compiled-effects artifact alike. So every
    # property here reaches its own route, and `Effect.Parameters` is empty on a stock effect —
    # recorded as a deviation by each type rather than worked around.
    #
    # ## The two by-value shapes
    #
    # `CNA_Vector3` is three floats, so both its eightbytes are SSE-class: the manifest expands it
    # with `by_value_sse` and this packs the components into the two `double`s that reach `xmm0`
    # and `xmm1`. `CNA_Matrix` is 64 bytes, which is MEMORY class: `by_value_memory` expands it
    # into five register fillers and eight stack eightbytes, and this supplies those eight.
    module StockEffectSupport
      module_function

      # A `Vector3` as the two SSE eightbytes its by-value expansion carries. The trailing four
      # bytes of the second eightbyte are padding the callee does not read.
      def vector3_eightbytes(value)
        ([value.X, value.Y, value.Z, 0.0].pack("e4")).unpack("d2")
      end

      def read_vector3(symbol, *leading)
        buffer = Fiddle::Pointer.malloc(16, Fiddle::RUBY_FREE)
        buffer[0, 16] = "\0" * 16
        CNA::Native.library.call(symbol, *leading, buffer)
        buffer[0, 12].unpack("e3")
      end

      # A `Matrix` as the eight stack eightbytes its MEMORY-class expansion carries, in the row
      # order `CNA_Matrix` declares — `m11` through `m44`.
      def matrix_eightbytes(value)
        MATRIX_FIELDS.map { |name| value.__send__(name) }.pack("e16").unpack("Q8")
      end

      def read_matrix(symbol, *leading)
        buffer = Fiddle::Pointer.malloc(64, Fiddle::RUBY_FREE)
        buffer[0, 64] = "\0" * 64
        CNA::Native.library.call(symbol, *leading, buffer)
        buffer[0, 64].unpack("e16")
      end

      def read_float(symbol, *leading)
        buffer = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
        buffer[0, 4] = "\0" * 4
        CNA::Native.library.call(symbol, *leading, buffer)
        buffer[0, 4].unpack1("e")
      end

      def read_boolean(symbol, *leading)
        buffer = Fiddle::Pointer.malloc(1, Fiddle::RUBY_FREE)
        buffer[0, 1] = "\0"
        CNA::Native.library.call(symbol, *leading, buffer)
        !buffer[0, 1].unpack1("C").zero?
      end

      MATRIX_FIELDS = %i[M11 M12 M13 M14 M21 M22 M23 M24 M31 M32 M33 M34 M41 M42 M43 M44].freeze
    end
  end
end
