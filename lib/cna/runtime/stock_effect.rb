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
    # every property here reaches its own route, and none of them goes near the parameter
    # collection. Four of the five publish one anyway — `SkinnedEffect` 12, `AlphaTestEffect` 6,
    # `DualTextureEffect` 5, `EnvironmentMapEffect` 12 — and `BasicEffect` alone answers zero on
    # every qualified artifact. That asymmetry is an upstream gap rather than a shape, recorded in
    # `docs/stock-effect-parameter-upstream-defect.md` and fixed upstream after the 0.21.0 pin.
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

      # ------------------------------------------------------------------ the shared members
      #
      # `IEffectMatrices`, `IEffectFog` and `IEffectLights` are one contract each in XNA and one
      # route family each in CNA, so each is written once here and mixed into every stock effect
      # that declares it. The XNA interface module is included beside it for conformance; this
      # supplies the behaviour.
      #
      # Each mixin reaches the effect's own `native_handle`, so nothing here knows which effect it
      # is on — which is the point, because `cna_effect_matrices_*`, `cna_effect_fog_*` and
      # `cna_effect_lights_*` do not either.

      # The value-and-type plumbing every stock effect member goes through.
      module Values
        private

        def stock_vector(symbol)
          Microsoft::Xna::Framework::Vector3.new(*StockEffectSupport.read_vector3(symbol, native_handle))
        end

        def stock_set_vector(symbol, value, name)
          unless value.instance_of?(Microsoft::Xna::Framework::Vector3)
            raise ::TypeError, "#{name} must be a Vector3"
          end

          CNA::Native.library.call(symbol, native_handle, *StockEffectSupport.vector3_eightbytes(value))
          value
        end

        def stock_float(symbol) = StockEffectSupport.read_float(symbol, native_handle)

        def stock_set_float(symbol, value, name)
          number = CNA::Runtime::Numeric.f32(value)
          raise ::TypeError, "#{name} must be a number" if number.nil?

          CNA::Native.library.call(symbol, native_handle, number)
          value
        end

        def stock_boolean(symbol) = StockEffectSupport.read_boolean(symbol, native_handle)

        def stock_set_boolean(symbol, value, name)
          raise ::TypeError, "#{name} must be true or false" unless value == true || value == false

          CNA::Native.library.call(symbol, native_handle, value ? 1 : 0)
          value
        end

        # CNA retains a texture and hands back only a handle, and this ABI has no route from a
        # native object back to one — the rule `TextureCollection` records — so every stock effect's
        # texture getter answers the object it was given.
        def stock_set_texture(symbol, value, name, *trailing)
          unless value.nil? || value.is_a?(Microsoft::Xna::Framework::Graphics::Texture2D)
            raise ::TypeError, "#{name} must be a Texture2D or nil"
          end

          CNA::Native.library.call(symbol, native_handle, *trailing,
                                   value.nil? ? 0 : value.__send__(:native_handle))
          value
        end
      end

      # `IEffectMatrices`: three `Matrix` properties, each a MEMORY-class by-value write.
      module Matrices
        include Values

        def World = stock_matrix("cna_effect_matrices_get_world")

        def World=(value)
          stock_set_matrix("cna_effect_matrices_set_world", value, "World")
        end

        def View = stock_matrix("cna_effect_matrices_get_view")

        def View=(value)
          stock_set_matrix("cna_effect_matrices_set_view", value, "View")
        end

        def Projection = stock_matrix("cna_effect_matrices_get_projection")

        def Projection=(value)
          stock_set_matrix("cna_effect_matrices_set_projection", value, "Projection")
        end

        private

        def stock_matrix(symbol)
          Microsoft::Xna::Framework::Matrix.new(*StockEffectSupport.read_matrix(symbol, native_handle))
        end

        def stock_set_matrix(symbol, value, name)
          unless value.instance_of?(Microsoft::Xna::Framework::Matrix)
            raise ::TypeError, "#{name} must be a Matrix"
          end

          CNA::Native.library.call(symbol, native_handle, 0, 0, 0, 0, 0,
                                   *StockEffectSupport.matrix_eightbytes(value))
          value
        end
      end

      # `IEffectFog`: four properties over `cna_effect_fog_*`.
      module Fog
        include Values

        def FogEnabled = stock_boolean("cna_effect_fog_get_enabled")

        def FogEnabled=(value)
          stock_set_boolean("cna_effect_fog_set_enabled", value, "FogEnabled")
        end

        def FogStart = stock_float("cna_effect_fog_get_start")

        def FogStart=(value)
          stock_set_float("cna_effect_fog_set_start", value, "FogStart")
        end

        def FogEnd = stock_float("cna_effect_fog_get_end")

        def FogEnd=(value)
          stock_set_float("cna_effect_fog_set_end", value, "FogEnd")
        end

        def FogColor = stock_vector("cna_effect_fog_get_color")

        def FogColor=(value)
          stock_set_vector("cna_effect_fog_set_color", value, "FogColor")
        end
      end

      # `IEffectLights`: the switch, the ambient colour, the three lights and the preset.
      #
      # `cna_effect_lights_get_directional_light` hands back a **fresh** owned view on every call —
      # measured — so the three are acquired once in `build_stock_lights` and held, which is the
      # rule the whole `Effect` object graph already follows.
      module Lights
        include Values

        def LightingEnabled = stock_boolean("cna_effect_lights_get_enabled")

        def LightingEnabled=(value)
          stock_set_boolean("cna_effect_lights_set_enabled", value, "LightingEnabled")
        end

        def AmbientLightColor = stock_vector("cna_effect_lights_get_ambient_color")

        def AmbientLightColor=(value)
          stock_set_vector("cna_effect_lights_set_ambient_color", value, "AmbientLightColor")
        end

        def DirectionalLight0 = @stock_lights[0]
        def DirectionalLight1 = @stock_lights[1]
        def DirectionalLight2 = @stock_lights[2]

        # `set_LightingEnabled(true)` then `EffectHelpers.EnableDefaultLighting(l0, l1, l2)`, whose
        # return value becomes `AmbientLightColor`. `cna_effect_lights_enable_default` performs the
        # whole preset and — measured — produces XNA's own values, so the three managed caches are
        # re-read rather than recomputed.
        def EnableDefaultLighting
          CNA::Native.library.call("cna_effect_lights_enable_default", native_handle)
          @stock_lights.each { |light| light.__send__(:refresh_from_native) }
          nil
        end

        private

        def build_stock_lights
          @stock_light_views = []
          @stock_lights = ::Array.new(3) do |index|
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_effect_lights_get_directional_light", native_handle, index, output)
            handle = output[0, 8].unpack1("Q")
            @stock_light_views << handle
            Microsoft::Xna::Framework::Graphics::DirectionalLight.__send__(:from_native, handle)
          end.freeze
          nil
        end

        def release_stock_lights
          views = @stock_light_views
          @stock_light_views = []
          views&.each do |handle|
            CNA::Native.library.call("cna_directional_light_destroy", handle)
          rescue CNA::NativeError
            nil
          end
          nil
        end

        # The four fields `CacheEffectParameters(cloneSource)` copies, through the setters, so each
        # light's enabled-gated colour rule applies to the clone too.
        def copy_stock_lights(source)
          3.times do |index|
            target = @stock_lights[index]
            other = source.__send__(:"DirectionalLight#{index}")
            target.Direction = other.Direction
            target.DiffuseColor = other.DiffuseColor
            target.SpecularColor = other.SpecularColor
            target.Enabled = other.Enabled
          end
          nil
        end
      end
    end
  end
end
