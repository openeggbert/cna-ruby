# frozen_string_literal: true

require_relative "../../framework"

module Microsoft
  module Xna
    module Framework
      module Input
        # Only the pure managed XNA Touch value contracts are projected. There is no TouchPanel,
        # TouchCollection, TouchLocation, GestureSample, gesture recognition or touch device.
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
