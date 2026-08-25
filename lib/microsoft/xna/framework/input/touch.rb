# frozen_string_literal: true

require_relative "../../framework"

module Microsoft
  module Xna
    module Framework
      module Input
        # Only the pure managed XNA Touch value contracts are projected. There is no TouchPanel,
        # TouchCollection, gesture recognition or touch device: nothing here queries hardware, and
        # no path in this binding produces a TouchLocation.
        module Touch
          class TouchLocationState < CNA::Runtime::EnumValue
            extend CNA::Runtime::EnumType
            define_values({
              "Invalid" => 0,
              "Released" => 1,
              "Pressed" => 2,
              "Moved" => 3
            })
          end

          class GestureType < CNA::Runtime::EnumValue
            extend CNA::Runtime::EnumType
            define_values({
              "None" => 0, "Tap" => 1, "DoubleTap" => 2, "Hold" => 4,
              "HorizontalDrag" => 8, "VerticalDrag" => 16, "FreeDrag" => 32,
              "Pinch" => 64, "Flick" => 128, "DragComplete" => 256,
              "PinchComplete" => 512
            }, flags: true)
          end

          # Derived from the pinned Microsoft.Xna.Framework.Input.Touch.dll IL
          # (SHA-256 b0585224…). The struct stores seven private fields — id, state, x, y,
          # prevState, prevX, prevY — as four Single values and two enum values, never as Vector2
          # fields, so Position builds a fresh Vector2 on every read.
          #
          # Neither public constructor validates anything. The three-argument form leaves the
          # previous location empty: prevState is the literal 0, which is TouchLocationState.Invalid,
          # and prevX/prevY are 0.
          #
          # Equals and op_Equality deliberately disagree, and that is preserved rather than
          # normalised: Equals compares id, x, y, prevX and prevY, while op_Equality compares all
          # seven fields including both states. Every comparison is IL `bne.un`, so NaN is never
          # equal to itself. GetHashCode sums only id, x and y.
          class TouchLocation
            include CNA::Runtime::ValueSemantics

            N = CNA::Runtime::Numeric
            private_constant :N

            attr_reader :Id, :State

            def initialize(*arguments)
              unless [3, 5].include?(arguments.length)
                raise ArgumentError, "TouchLocation.new expects (id, state, position) or " \
                                     "(id, state, position, previousState, previousPosition)"
              end

              id, state, position, previous_state, previous_position = arguments
              @Id = N.int32(id, "id")
              @State = TouchLocationState.coerce(state)
              CNA::Runtime::GeometrySupport.require_type(position, Vector2)
              @x = N.f32(position.X)
              @y = N.f32(position.Y)
              if arguments.length == 5
                @PreviousState = TouchLocationState.coerce(previous_state)
                CNA::Runtime::GeometrySupport.require_type(previous_position, Vector2)
                @prev_x = N.f32(previous_position.X)
                @prev_y = N.f32(previous_position.Y)
              else
                @PreviousState = TouchLocationState::Invalid
                @prev_x = N.f32(0.0)
                @prev_y = N.f32(0.0)
              end
            end

            def Position = Vector2.new(@x, @y)

            # `brtrue` on prevState: anything other than Invalid has a previous location. The false
            # branch still fills the out value, with id -1 and everything else zero, so both halves
            # of the CLR result are returned rather than one being dropped.
            def TryGetPreviousLocation
              return [false, self.class.new(-1, TouchLocationState::Invalid, Vector2.new(0.0, 0.0))] if
                @PreviousState == TouchLocationState::Invalid

              [true, self.class.new(@Id, @PreviousState, Vector2.new(@prev_x, @prev_y))]
            end

            def Equals(other)
              other.instance_of?(self.class) &&
                @Id == other.Id &&
                @x == other.__send__(:x) && @y == other.__send__(:y) &&
                @prev_x == other.__send__(:prev_x) && @prev_y == other.__send__(:prev_y)
            end

            def GetHashCode = N.hash32_sum(@Id, N.single_hash(@x), N.single_hash(@y))
            # A bare uppercase token parses as a constant, so the reader needs an explicit receiver.
            def ToString = "{Position:#{self.Position.ToString}}"
            alias to_s ToString

            private

            attr_reader :x, :y, :prev_x, :prev_y, :PreviousState

            def value_components
              [@Id, @State, self.Position, @PreviousState, Vector2.new(@prev_x, @prev_y)]
            end
          end

          # Derived from the pinned Microsoft.Xna.Framework.Input.Touch.dll IL
          # (SHA-256 b0585224…). The constructor is pure storage: six assignments and a ret, with no
          # validation and no derived state, and each of the six get-only properties is a single
          # field read. Timestamp is a System.TimeSpan, which the BCL projection register maps to a
          # Ruby Float of seconds.
          #
          # The struct declares no Equals, GetHashCode, ToString or operator, so — exactly as
          # TouchPanelCapabilities does — none is projected: inventing one would claim a contract
          # XNA does not declare. Struct-valued reads answer fresh copies.
          #
          # Nothing in this binding produces a GestureSample. TouchPanel and all gesture recognition
          # remain absent; this is the value contract only.
          class GestureSample
            def initialize(gesture_type, timestamp, position, position2, delta, delta2)
              @GestureType = GestureType.coerce(gesture_type)
              @Timestamp = CNA::Runtime::BclProjection.time_span(timestamp)
              @_position = copy_vector(position)
              @_position2 = copy_vector(position2)
              @_delta = copy_vector(delta)
              @_delta2 = copy_vector(delta2)
            end

            attr_reader :GestureType, :Timestamp

            def Position = @_position.dup
            def Position2 = @_position2.dup
            def Delta = @_delta.dup
            def Delta2 = @_delta2.dup

            def dup
              self.class.new(@GestureType, @Timestamp, @_position, @_position2, @_delta, @_delta2)
            end

            def clone(freeze: true) = dup.tap { |value| value.freeze if freeze && frozen? }

            private

            def copy_vector(value)
              CNA::Runtime::GeometrySupport.require_type(value, Vector2)
              value.dup
            end
          end

          # The XNA struct declares only two read-only properties and no public constructor, so the
          # only reachable instance is the CLR default value: IsConnected false, MaximumTouchCount 0.
          # Nothing queries a device; TouchPanel.GetCapabilities is deliberately absent.
          class TouchPanelCapabilities
            PROPERTIES = {IsConnected: false, MaximumTouchCount: 0}.freeze
            private_constant :PROPERTIES

            attr_reader(*PROPERTIES.keys)

            def dup = self.class.new
            def clone(freeze: true) = dup.tap { |value| value.freeze if freeze && frozen? }

            private

            def initialize
              PROPERTIES.each { |name, default| instance_variable_set(:"@#{name}", default) }
            end
          end
        end
      end
    end
  end
end
