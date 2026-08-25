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

          # Derived from the pinned Microsoft.Xna.Framework.Input.Touch.dll IL
          # (SHA-256 b0585224…). The struct declares eight private TouchLocation slots and an
          # int32 count, never a list, which is why the whole type has a hard eight-location
          # ceiling and why its indexer is a switch rather than an array read.
          #
          # It is a read-only IList<TouchLocation>: `IsReadOnly` answers the literal `true`, and
          # `Insert`, `RemoveAt`, `Add`, `Clear`, `Remove` and the `Item` setter are each a
          # two-instruction body — `newobj System.NotSupportedException::.ctor(); throw`. Foundation
          # 30 mapped that exception to CNA::Runtime::NotSupportedError, a real StandardError
          # subclass, so an ordinary `rescue` catches it; Ruby's NotImplementedError would not be
          # caught, because it is a ScriptError. The CLR's parameterless constructor fills its
          # message from the localized framework resource Arg_NotSupportedException, which no XNA
          # member exposes observably and which is therefore not reproduced.
          #
          # Nothing in this binding produces a TouchCollection. TouchPanel, gesture recognition and
          # every touch device remain absent, and the internal `Update` that XNA's native input
          # layer drives is not projected. This is the value contract only.
          class TouchCollection
            include Enumerable

            N = CNA::Runtime::Numeric
            # The eight `location0`..`location7` fields the struct declares.
            LOCATION_SLOTS = 8
            private_constant :N, :LOCATION_SLOTS

            # `.ctor(TouchLocation[] touches)`: null touches throws ArgumentNullException("touches")
            # and more than eight throws ArgumentOutOfRangeException("touches"), both constructed in
            # this method's own IL with the parameter name as the ldstr operand. isConnected is then
            # set to the literal true and every location slot is zeroed before the loop.
            #
            # Each element is expanded through TouchLocation.TryGetPreviousLocation: when it answers
            # a previous location the new entry carries that location's state and position, and when
            # it does not the previous state is the literal 0 — TouchLocationState.Invalid — with a
            # zero previous position.
            def initialize(touches)
              raise ArgumentError, "touches" if touches.nil?
              raise TypeError, "touches must be an Array of TouchLocation" unless touches.instance_of?(::Array)
              raise RangeError, "touches" if touches.length > LOCATION_SLOTS

              touches.each { |touch| CNA::Runtime::GeometrySupport.require_type(touch, TouchLocation, "touches") }

              @is_connected = true
              @location_count = 0
              @locations = []
              touches.each do |touch|
                found, previous = touch.TryGetPreviousLocation
                if found
                  add_touch_location(touch.Id, touch.State, touch.Position,
                                     previous.State, previous.Position)
                else
                  add_touch_location(touch.Id, touch.State, touch.Position,
                                     TouchLocationState::Invalid, Vector2.new(0.0, 0.0))
                end
              end
            end

            def Count = @location_count
            def IsConnected = @is_connected
            # The getter is the literal `true`; there is no backing field and no way to change it.
            def IsReadOnly = true

            # `get_Item(int32)`: index < 0 or index >= Count throws
            # ArgumentOutOfRangeException("index"), constructed in this member's own IL, which the
            # thrown-exception register maps to RangeError. The struct is returned by value, so the
            # Ruby projection answers a fresh copy.
            def [](index)
              value = N.int32(index, "index")
              raise RangeError, "index" if value.negative? || value >= @location_count

              @locations[value > LOCATION_SLOTS - 1 ? LOCATION_SLOTS - 1 : value].dup
            end

            # `set_Item`, and every other mutating member, is an unconditional throw.
            # A setter cannot use Ruby's endless method definition syntax.
            def []=(index, value)
              raise CNA::Runtime::NotSupportedError
            end
            def Insert(index, item) = raise(CNA::Runtime::NotSupportedError)
            def RemoveAt(index) = raise(CNA::Runtime::NotSupportedError)
            def Add(item) = raise(CNA::Runtime::NotSupportedError)
            def Clear = raise(CNA::Runtime::NotSupportedError)
            def Remove(item) = raise(CNA::Runtime::NotSupportedError)

            # A forward scan over 0...Count comparing with TouchLocation::op_Equality — all seven
            # fields, not the narrower Equals — answering the first match or -1.
            def IndexOf(item)
              CNA::Runtime::GeometrySupport.require_type(item, TouchLocation, "item")
              index = 0
              while index < @location_count
                return index if self[index] == item

                index += 1
              end
              -1
            end

            # `IndexOf(item) < 0` negated: exactly the same scan, never a separate comparison.
            def Contains(item) = self.IndexOf(item) >= 0

            # `CopyTo(TouchLocation[], int32)`: null array throws ArgumentNullException("array"), and
            # both a negative arrayIndex and a destination shorter than arrayIndex + Count throw
            # ArgumentOutOfRangeException("arrayIndex"). The CLR compares in Int64, so no overflow
            # is possible; Ruby integers are unbounded, so the same comparison is exact.
            def CopyTo(array, array_index)
              raise ArgumentError, "array" if array.nil?

              CNA::Runtime::GeometrySupport.require_array(array, "array", mutable: true)
              index = N.int32(array_index, "arrayIndex")
              raise RangeError, "arrayIndex" if index.negative?
              raise RangeError, "arrayIndex" if array.length < index + @location_count

              offset = 0
              while offset < @location_count
                array[index + offset] = self[offset]
                offset += 1
              end
              nil
            end

            # `FindById(int32, out TouchLocation)`: the out parameter follows the Boolean return as
            # an ordered Array, because the CLR fills it on both branches — the match on success and
            # `initobj`, the CLR default TouchLocation, on failure. Neither half is dropped.
            def FindById(id)
              wanted = N.int32(id, "id")
              index = 0
              while index < @location_count
                return [true, self[index]] if self[index].Id == wanted

                index += 1
              end
              [false, TouchLocation.new(0, TouchLocationState::Invalid, Vector2.new(0.0, 0.0))]
            end

            # `GetEnumerator()` copies the collection struct into the enumerator (`ldobj`), so the
            # enumerator walks a snapshot rather than holding a reference back.
            def GetEnumerator = Enumerator.__send__(:new, dup)

            # Ruby language support, not an XNA identity: `each` is the one Ruby identity that
            # carries CLR GetEnumerator, and everything Enumerable contributes is derived from it.
            def each
              enumerator = self.GetEnumerator
              return to_enum(:each) unless block_given?

              yield enumerator.Current while enumerator.MoveNext
              self
            end

            def dup
              copy = allocate_copy
              copy.__send__(:initialize_copy_state, @is_connected, @location_count, @locations)
              copy
            end

            def clone(freeze: true) = dup.tap { |value| value.freeze if freeze && frozen? }

            # `TouchCollection+Enumerator`, addressed the way the reference contract spells a nested
            # type. Its only constructor is `assembly`, so `new` is private exactly as the
            # constructor-free class rule requires, and the enumerator starts before the first
            # element with `position` at -1.
            #
            # `IEnumerator.Reset` exists in the IL as a private explicit interface implementation
            # and is not part of the selected surface, so it is deliberately not projected.
            class Enumerator
              def initialize(collection)
                @collection = collection
                @position = -1
              end
              private_class_method :new

              # `get_Current` calls TouchCollection::get_Item(position) with no guard of its own, so
              # reading it before the first MoveNext (position -1) or after exhaustion
              # (position == Count) raises exactly what the indexer raises.
              def Current = @collection[@position]

              # position += 1; answer true while it is below Count, otherwise clamp it to Count and
              # answer false. Clamping is what keeps a second MoveNext past the end from walking
              # further.
              def MoveNext
                @position += 1
                return true if @position < @collection.Count

                @position = @collection.Count
                false
              end

              # The IL body is a bare `ret`: the enumerator holds nothing to release.
              def Dispose = nil
            end

            private

            # `AddTouchLocation`: the count is read, incremented, and the *old* value selects the
            # slot. A value of 8 or more selects nothing and stores nothing while still leaving the
            # count incremented, which is faithfully preserved even though the constructor's
            # eight-element ceiling makes it unreachable from the public surface.
            def add_touch_location(id, state, position, previous_state, previous_position)
              slot = @location_count
              @location_count += 1
              return if slot >= LOCATION_SLOTS

              @locations[slot] = TouchLocation.new(id, state, position, previous_state, previous_position)
            end

            def allocate_copy = self.class.allocate

            def initialize_copy_state(is_connected, location_count, locations)
              @is_connected = is_connected
              @location_count = location_count
              @locations = locations.map(&:dup)
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
