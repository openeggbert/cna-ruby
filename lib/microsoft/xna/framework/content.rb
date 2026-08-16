require_relative 'graphics'

module Microsoft
  module Xna
    module Framework
      module Content
        class ContentManager
          attr_accessor :RootDirectory
          def initialize(serviceProvider, rootDirectory = "Content")
            @RootDirectory = rootDirectory
          end
          def Load(assetName)
            # Placeholder
            Graphics::Texture2D.new(nil, 256, 256)
          end
        end
      end
    end
  end
end
