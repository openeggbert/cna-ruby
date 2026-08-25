# frozen_string_literal: true

module Microsoft
  module Xna
    module Framework
      # XNA interfaces project to Ruby modules whose members raise NotImplementedError, exactly as
      # the PackedVector interface contracts already do. They are abstract contracts: no concrete
      # type in this foundation includes them yet, and including one into a partial runtime type
      # would add public members that type's selected surface does not declare.
      module IGameComponent
        def Initialize = raise(NotImplementedError, "IGameComponent#Initialize")
      end

      module IGraphicsDeviceManager
        def CreateDevice = raise(NotImplementedError, "IGraphicsDeviceManager#CreateDevice")
        def BeginDraw = raise(NotImplementedError, "IGraphicsDeviceManager#BeginDraw")
        def EndDraw = raise(NotImplementedError, "IGraphicsDeviceManager#EndDraw")
      end

      # One CLR public event projects to exactly one public Ruby event reader keeping the XNA
      # spelling, whose value is the generic CNA::Runtime::Event subscription primitive. On an
      # abstract contract the reader raises NotImplementedError like every other member: an
      # interface declares the event identity and never owns an invocation list.
      module IUpdateable
        extend CNA::Runtime::EventOwner

        def Update(gameTime) = raise(NotImplementedError, "IUpdateable#Update")
        def Enabled = raise(NotImplementedError, "IUpdateable#Enabled")
        def UpdateOrder = raise(NotImplementedError, "IUpdateable#UpdateOrder")
        xna_abstract_event :EnabledChanged, "IUpdateable#EnabledChanged"
        xna_abstract_event :UpdateOrderChanged, "IUpdateable#UpdateOrderChanged"
      end

      module IDrawable
        extend CNA::Runtime::EventOwner

        def Draw(gameTime) = raise(NotImplementedError, "IDrawable#Draw")
        def Visible = raise(NotImplementedError, "IDrawable#Visible")
        def DrawOrder = raise(NotImplementedError, "IDrawable#DrawOrder")
        xna_abstract_event :VisibleChanged, "IDrawable#VisibleChanged"
        xna_abstract_event :DrawOrderChanged, "IDrawable#DrawOrderChanged"
      end
    end
  end
end
