# frozen_string_literal: true

module Microsoft
  module Xna
    module Framework
      class CurveContinuity < CNA::Runtime::EnumValue
        extend CNA::Runtime::EnumType
        define_values({"Smooth" => 0, "Step" => 1})
      end

      class CurveLoopType < CNA::Runtime::EnumValue
        extend CNA::Runtime::EnumType
        define_values({"Constant" => 0, "Cycle" => 1, "CycleOffset" => 2, "Oscillate" => 3, "Linear" => 4})
      end

      class CurveTangent < CNA::Runtime::EnumValue
        extend CNA::Runtime::EnumType
        define_values({"Flat" => 0, "Linear" => 1, "Smooth" => 2})
      end

      class CurveKey
        N = CNA::Runtime::Numeric
        private_constant :N

        attr_reader :Position, :Value, :TangentIn, :TangentOut, :Continuity

        def initialize(*arguments)
          position, value, tangent_in, tangent_out, continuity = case arguments.length
                                                                 when 2
                                                                   [arguments[0], arguments[1], 0.0, 0.0,
                                                                    CurveContinuity::Smooth]
                                                                 when 4
                                                                   [*arguments, CurveContinuity::Smooth]
                                                                 when 5
                                                                   arguments
                                                                 else
                                                                   raise ArgumentError,
                                                                         "CurveKey.new expects (position, value), " \
                                                                         "(position, value, tangentIn, tangentOut), or " \
                                                                         "(position, value, tangentIn, tangentOut, continuity)"
                                                                 end
          @Position = N.f32(position)
          self.Value = value
          self.TangentIn = tangent_in
          self.TangentOut = tangent_out
          self.Continuity = continuity
        end

        def Value=(value)
          @Value = N.f32(value)
        end

        def TangentIn=(value)
          @TangentIn = N.f32(value)
        end

        def TangentOut=(value)
          @TangentOut = N.f32(value)
        end

        def Continuity=(value)
          @Continuity = CurveContinuity.coerce(value)
        end

        def Clone = CurveKey.new(@Position, @Value, @TangentIn, @TangentOut, @Continuity)

        def Equals(other)
          other.is_a?(CurveKey) &&
            other.Position == @Position &&
            other.Value == @Value &&
            other.TangentIn == @TangentIn &&
            other.TangentOut == @TangentOut &&
            other.Continuity == @Continuity
        end

        def ==(other) = self.Equals(other)
        def !=(other) = !self.Equals(other)
        alias eql? ==

        def GetHashCode
          N.hash32_sum(
            N.single_hash(@Position), N.single_hash(@Value),
            N.single_hash(@TangentIn), N.single_hash(@TangentOut), @Continuity.to_i
          )
        end
        alias hash GetHashCode

        def CompareTo(other)
          raise TypeError, "other must be CurveKey" unless other.is_a?(CurveKey)

          return 0 if @Position == other.Position

          @Position < other.Position ? -1 : 1
        end
      end

      class CurveKeyCollection
        N = CNA::Runtime::Numeric
        SINGLE_EPSILON = [1].pack("L<").unpack1("e")
        private_constant :N, :SINGLE_EPSILON

        def initialize
          @keys = []
          @time_range = 0.0
          @inverse_time_range = 0.0
          @cache_available = true
          @version = 0
        end

        def Count = @keys.length
        def IsReadOnly = false

        def [](index)
          @keys.fetch(valid_index(index))
        end

        def []=(index, value)
          require_key!(value, "value")
          valid = valid_index(index)
          if @keys[valid].Position == value.Position
            @keys[valid] = value
            @version += 1
          else
            @keys.delete_at(valid)
            @version += 1
            self.Add(value)
          end
          value
        end

        def IndexOf(item)
          return -1 if item.nil?

          require_key!(item, "item")
          @keys.each_with_index { |candidate, index| return index if candidate.Equals(item) }
          -1
        end

        def RemoveAt(index)
          @keys.delete_at(valid_index(index))
          @cache_available = false
          @version += 1
          nil
        end

        def Add(item)
          require_key!(item, "item")
          index = binary_search(item)
          if index >= 0
            index += 1 while index < @keys.length && item.Position == @keys[index].Position
          else
            index = ~index
          end
          @keys.insert(index, item)
          @cache_available = false
          @version += 1
          nil
        end

        def Clear
          @keys.clear
          @time_range = 0.0
          @inverse_time_range = 0.0
          @cache_available = false
          @version += 1
          nil
        end

        def Contains(item) = self.IndexOf(item) >= 0

        def CopyTo(array, array_index)
          raise TypeError, "array must be an Array" unless array.instance_of?(Array)

          index = N.int32(array_index, "arrayIndex")
          raise IndexError, "arrayIndex must be non-negative" if index.negative?
          raise ArgumentError, "destination Array is too small" if index > array.length - @keys.length

          @keys.each_with_index { |key, offset| array[index + offset] = key }
          @cache_available = false
          nil
        end

        def Remove(item)
          index = self.IndexOf(item)
          @cache_available = false
          return false if index.negative?

          @keys.delete_at(index)
          @version += 1
          true
        end

        def GetEnumerator
          expected_version = @version
          index = 0
          Enumerator.new do |yielder|
            while index < @keys.length
              verify_enumerator_version(expected_version)
              yielder << @keys[index]
              index += 1
            end
            verify_enumerator_version(expected_version)
            nil
          end
        end

        def Clone
          copy = CurveKeyCollection.new
          copy.instance_variable_set(:@keys, @keys.dup)
          copy.instance_variable_set(:@time_range, @time_range)
          copy.instance_variable_set(:@inverse_time_range, @inverse_time_range)
          copy.instance_variable_set(:@cache_available, true)
          copy
        end

        private

        def valid_index(index)
          value = N.int32(index, "index")
          raise IndexError, "CurveKeyCollection index is out of range" if value.negative? || value >= @keys.length

          value
        end

        def require_key!(value, name)
          raise TypeError, "#{name} must be CurveKey" unless value.is_a?(CurveKey)
        end

        def binary_search(item)
          low = 0
          high = @keys.length - 1
          while low <= high
            middle = low + ((high - low) >> 1)
            comparison = @keys[middle].CompareTo(item)
            return middle if comparison.zero?

            if comparison.negative?
              low = middle + 1
            else
              high = middle - 1
            end
          end
          ~low
        end

        def verify_enumerator_version(expected)
          return if expected == @version

          raise RuntimeError, "CurveKeyCollection was modified during enumeration"
        end

        def ensure_cache
          return if @cache_available

          @time_range = 0.0
          @inverse_time_range = 0.0
          if @keys.length > 1
            @time_range = N.sub32(@keys[-1].Position, @keys[0].Position)
            @inverse_time_range = N.div32(1.0, @time_range) if @time_range > SINGLE_EPSILON
          end
          @cache_available = true
        end

        def time_range
          ensure_cache
          @time_range
        end

        def inverse_time_range
          ensure_cache
          @inverse_time_range
        end
      end

      class Curve
        N = CNA::Runtime::Numeric
        INT32_MIN = -2_147_483_648
        TANGENT_EPSILON = N.f32(1.1920929E-07)
        private_constant :N, :INT32_MIN, :TANGENT_EPSILON

        attr_reader :PreLoop, :PostLoop, :Keys

        def initialize
          @PreLoop = CurveLoopType::Constant
          @PostLoop = CurveLoopType::Constant
          @Keys = CurveKeyCollection.new
        end

        def PreLoop=(value)
          @PreLoop = CurveLoopType.coerce(value)
        end

        def PostLoop=(value)
          @PostLoop = CurveLoopType.coerce(value)
        end

        def IsConstant = @Keys.Count <= 1

        def Clone
          copy = Curve.new
          copy.PreLoop = @PreLoop
          copy.PostLoop = @PostLoop
          copy.instance_variable_set(:@Keys, @Keys.Clone)
          copy
        end

        def ComputeTangent(*arguments)
          key_index, tangent_in_type, tangent_out_type = case arguments.length
                                                         when 2
                                                           [arguments[0], arguments[1], arguments[1]]
                                                         when 3
                                                           arguments
                                                         else
                                                           raise ArgumentError,
                                                                 "ComputeTangent expects keyIndex and one or two tangent modes"
                                                         end
          index = valid_key_index(key_index)
          tangent_in = CurveTangent.coerce(tangent_in_type)
          tangent_out = CurveTangent.coerce(tangent_out_type)
          key = @Keys[index]
          previous_position = current_position = next_position = key.Position
          previous_value = current_value = next_value = key.Value
          if index.positive?
            previous_position = @Keys[index - 1].Position
            previous_value = @Keys[index - 1].Value
          end
          if index + 1 < @Keys.Count
            next_position = @Keys[index + 1].Position
            next_value = @Keys[index + 1].Value
          end

          key.TangentIn = tangent_value(
            tangent_in, previous_position, current_position, next_position,
            previous_value, current_value, next_value, incoming: true
          )
          key.TangentOut = tangent_value(
            tangent_out, previous_position, current_position, next_position,
            previous_value, current_value, next_value, incoming: false
          )
          nil
        end

        def ComputeTangents(*arguments)
          tangent_in, tangent_out = case arguments.length
                                    when 1 then [arguments[0], arguments[0]]
                                    when 2 then arguments
                                    else raise ArgumentError, "ComputeTangents expects one or two tangent modes"
                                    end
          incoming = CurveTangent.coerce(tangent_in)
          outgoing = CurveTangent.coerce(tangent_out)
          @Keys.Count.times { |index| self.ComputeTangent(index, incoming, outgoing) }
          nil
        end

        def Evaluate(position)
          sample = N.f32(position)
          return 0.0 if @Keys.Count.zero?
          return @Keys[0].Value if @Keys.Count == 1

          first = @Keys[0]
          last = @Keys[@Keys.Count - 1]
          offset = 0.0
          if sample < first.Position
            return first.Value if @PreLoop == CurveLoopType::Constant
            return linear_extrapolation(first, sample, incoming: true) if @PreLoop == CurveLoopType::Linear

            sample, offset = loop_sample(sample, first, last, @PreLoop)
          elsif last.Position < sample
            return last.Value if @PostLoop == CurveLoopType::Constant
            return linear_extrapolation(last, sample, incoming: false) if @PostLoop == CurveLoopType::Linear

            sample, offset = loop_sample(sample, first, last, @PostLoop)
          end

          start_key, end_key, amount = find_segment(sample)
          N.add32(offset, interpolate(start_key, end_key, amount))
        end

        private

        def valid_key_index(index)
          value = N.int32(index, "keyIndex")
          raise IndexError, "keyIndex is out of range" if value.negative? || value >= @Keys.Count

          value
        end

        def tangent_value(type, previous_position, current_position, next_position,
                          previous_value, current_value, next_value, incoming:)
          return 0.0 if type == CurveTangent::Flat
          if type == CurveTangent::Linear
            return incoming ? N.sub32(current_value, previous_value) : N.sub32(next_value, current_value)
          end

          position_span = N.sub32(next_position, previous_position)
          value_span = N.sub32(next_value, previous_value)
          return 0.0 if value_span.abs < TANGENT_EPSILON

          side_span = if incoming
                        N.sub32(previous_position, current_position).abs
                      else
                        N.sub32(next_position, current_position).abs
                      end
          N.div32(N.mul32(value_span, side_span), position_span)
        end

        def linear_extrapolation(key, sample, incoming:)
          tangent = incoming ? key.TangentIn : key.TangentOut
          N.sub32(key.Value, N.mul32(tangent, N.sub32(key.Position, sample)))
        end

        def loop_sample(sample, first, last, mode)
          cycle = calculate_cycle(sample, first)
          range = @Keys.__send__(:time_range)
          remainder = N.sub32(sample, N.add32(first.Position, N.mul32(cycle, range)))
          if mode == CurveLoopType::Cycle
            [N.add32(first.Position, remainder), 0.0]
          elsif mode == CurveLoopType::CycleOffset
            [N.add32(first.Position, remainder), N.mul32(N.sub32(last.Value, first.Value), cycle)]
          elsif clr_float_to_int32(cycle).odd?
            [N.sub32(last.Position, remainder), 0.0]
          else
            [N.add32(first.Position, remainder), 0.0]
          end
        end

        def calculate_cycle(sample, first)
          value = N.mul32(N.sub32(sample, first.Position), @Keys.__send__(:inverse_time_range))
          value = N.sub32(value, 1.0) if value < 0.0
          N.f32(clr_float_to_int32(value))
        end

        def clr_float_to_int32(value)
          number = N.f32(value)
          return INT32_MIN unless number.finite? && number >= INT32_MIN && number < 2_147_483_648

          number.to_i
        end

        def find_segment(sample)
          amount = sample
          start_key = @Keys[0]
          end_key = nil
          (1...@Keys.Count).each do |index|
            end_key = @Keys[index]
            if end_key.Position >= sample
              start_position = start_key.Position.to_f
              end_position = end_key.Position.to_f
              target_position = sample.to_f
              span = end_position - start_position
              amount = 0.0
              amount = N.f32((target_position - start_position) / span) if span > 1.0e-10
              break
            end
            start_key = end_key
          end
          [start_key, end_key, amount]
        end

        def interpolate(start_key, end_key, amount)
          if start_key.Continuity == CurveContinuity::Step
            return amount < 1.0 ? start_key.Value : end_key.Value
          end

          MathHelper.Hermite(
            start_key.Value, start_key.TangentOut,
            end_key.Value, end_key.TangentIn, amount
          )
        end
      end
    end
  end
end
