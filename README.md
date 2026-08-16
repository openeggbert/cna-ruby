# CNA Ruby Binding

> **Status: In progress - NOT YET FUNCTIONAL**


Ruby bindings for the CNA framework, providing an XNA 4.0 compatible API.

## Namespace
All classes are under the `Microsoft::Xna::Framework` module.

## Usage
Include the following in your Ruby script:
```ruby
require 'microsoft/xna/framework'
require 'microsoft/xna/framework/graphics'
require 'microsoft/xna/framework/input'
require 'microsoft/xna/framework/content'
```

## Structure
- `lib/microsoft/xna/framework.rb`: Core types (Vector2, Color, Game).
- `lib/microsoft/xna/framework/graphics.rb`: Graphics API (GraphicsDevice, SpriteBatch, BasicEffect).
- `lib/microsoft/xna/framework/input.rb`: Input handling (Keyboard).
- `lib/microsoft/xna/framework/content.rb`: Content management.
