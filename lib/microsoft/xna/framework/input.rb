module Microsoft
  module Xna
    module Framework
      module Input
        module Keys
          Escape = 27
          # Add more
        end

        class KeyboardState
          def initialize(keys_down = [])
            @keys_down = keys_down
          end
          def IsKeyDown(key)
            @keys_down.include?(key)
          end
        end

        class Keyboard
          def self.GetState
            KeyboardState.new
          end
        end
      end
    end
  end
end
