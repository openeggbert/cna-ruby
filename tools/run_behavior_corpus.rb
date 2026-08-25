# frozen_string_literal: true

require "digest"
require "json"
require_relative "../lib/cna"

F = Microsoft::Xna::Framework
PV = F::Graphics::PackedVector
I = F::Input
G = F::Graphics
CLEAR_OPTIONS_SIGNATURE = JSON.parse(
  File.read(File.expand_path("api_compat/signatures.json", __dir__))
).fetch("types").find do |type|
  type.fetch("name") == "Microsoft.Xna.Framework.Graphics.ClearOptions"
end
DEPTH_FORMAT_SIGNATURE = JSON.parse(
  File.read(File.expand_path("api_compat/signatures.json", __dir__))
).fetch("types").find do |type|
  type.fetch("name") == "Microsoft.Xna.Framework.Graphics.DepthFormat"
end
PRIMITIVE_TYPE_SIGNATURE = JSON.parse(
  File.read(File.expand_path("api_compat/signatures.json", __dir__))
).fetch("types").find do |type|
  type.fetch("name") == "Microsoft.Xna.Framework.Graphics.PrimitiveType"
end
GRAPHICS_DEVICE_STATUS_SIGNATURE = JSON.parse(
  File.read(File.expand_path("api_compat/signatures.json", __dir__))
).fetch("types").find do |type|
  type.fetch("name") == "Microsoft.Xna.Framework.Graphics.GraphicsDeviceStatus"
end
GRAPHICS_PROFILE_SIGNATURE = JSON.parse(
  File.read(File.expand_path("api_compat/signatures.json", __dir__))
).fetch("types").find do |type|
  type.fetch("name") == "Microsoft.Xna.Framework.Graphics.GraphicsProfile"
end

A = F::Audio
M = F::Media
TOUCH = F::Input::Touch
CONTENT = F::Content
BATCH_SIGNATURES = JSON.parse(
  File.read(File.expand_path("api_compat/signatures.json", __dir__))
).fetch("types").to_h { |type| [type.fetch("name"), type] }
BATCH_REFERENCE = JSON.parse(
  File.read(File.expand_path("api_compat/reference/xna40-windows-runtime-contract.json", __dir__))
).fetch("types").to_h { |type| [type.fetch("name"), type] }
# Derived from the hash-pinned original XNA assemblies by tools/api_compat/build_il_inventory.rb.
# It carries no Microsoft-owned bytes, only measured structural facts and the assembly hashes.
IL_INVENTORY = JSON.parse(File.read(File.expand_path("../docs/generated/xna-il-inventory.json", __dir__)))

def batch_enum_type(clr_name)
  clr_name.split(".").reduce(Object) { |scope, segment| scope.const_get(segment, false) }
end

def vector(value) = F::Vector2.new(*value)
def vector3(value) = F::Vector3.new(*value)
def vector4(value) = F::Vector4.new(*value)
def rectangle(value) = F::Rectangle.new(*value)
def color(value) = F::Color.new(*value)
def box(value) = F::BoundingBox.new(vector3(value[0]), vector3(value[1]))
def sphere(value) = F::BoundingSphere.new(vector3(value[0]), value[1])
def vector_result(value) = [value.X, value.Y]
def vector3_result(value) = [value.X, value.Y, value.Z]
def vector4_result(value) = [value.X, value.Y, value.Z, value.W]
def quaternion_result(value) = [value.X, value.Y, value.Z, value.W]
def matrix_result(value) = (1..4).flat_map { |row| (1..4).map { |column| value.public_send("M#{row}#{column}") } }
def rectangle_result(value) = [value.X, value.Y, value.Width, value.Height]
def color_result(value) = [value.R, value.G, value.B, value.A]
def hex32(value)
  narrowed = CNA::Runtime::Numeric.f32(value)
  if narrowed.nan?
    sign = [narrowed].pack("E").unpack1("Q<") >> 63
    return sign.zero? ? "7FC00000" : "FFC00000"
  end
  [narrowed].pack("e").unpack1("L<").to_s(16).upcase.rjust(8, "0")
end
def hex_values(values) = values.map { |value| hex32(value) }
def float_from_bits(value) = [value].pack("L").unpack1("f")
def packed_type(name) = PV.const_get(name, false)
def button(value) = I::ButtonState.coerce(value)
def buttons(value) = I::Buttons.coerce(value)
def mouse_state(value)
  I::MouseState.new(value[0], value[1], value[2], button(value[3]), button(value[4]),
                    button(value[5]), button(value[6]), button(value[7]))
end

def qualified_viewport
  G::Viewport.new(13, -7, 641, 479).tap do |viewport|
    viewport.MinDepth = 0.2
    viewport.MaxDepth = 0.85
  end
end

def viewport_matrices
  world = F::Matrix.new(
    1.25, -0.375, 0.5, 0.0625, 0.2, 0.875, -0.45, -0.03125,
    -0.15, 0.3, 1.1, 0.125, 3.5, -2.25, 4.75, 1.0
  )
  view = F::Matrix.new(
    0.9, 0.1, -0.2, 0.015625, -0.05, 1.05, 0.125, -0.0078125,
    0.225, -0.175, 0.8, 0.03125, -1.5, 2.75, -3.25, 1.0
  )
  projection = F::Matrix.new(
    1.1, -0.075, 0.04, 0.2, 0.125, 0.95, -0.06, -0.1,
    -0.035, 0.08, 1.2, 0.3, 0.15, -0.2, 0.25, 0.9
  )
  [world, view, projection]
end

def viewport_matrix_with_w(bits)
  F::Matrix.Identity.tap { |matrix| matrix.M44 = CNA::Runtime::Numeric.f32_from_bits(bits) }
end
def invoke_projection(instance, name)
  arity = instance.method(name).arity
  instance.public_send(name, *Array.new(arity.negative? ? 0 : arity, nil))
end

# A minimal IGameComponent for the collection observations: the contract and nothing else, so the
# rows depend on no later milestone.
def corpus_component(label = nil)
  Class.new do
    include Microsoft::Xna::Framework::IGameComponent
    define_method(:initialize) { @label = label }
    attr_reader :label
    def Initialize = nil
  end.new
end

# Component fixtures for the Foundation 37 rows: the XNA contracts and nothing else, so the rows
# depend on no later milestone.
class CorpusUpdateable
  extend CNA::Runtime::EventOwner
  include Microsoft::Xna::Framework::IGameComponent
  include Microsoft::Xna::Framework::IUpdateable

  xna_event :EnabledChanged
  xna_event :UpdateOrderChanged

  attr_reader :label, :log, :Enabled, :UpdateOrder

  def initialize(label, log = [], order: 0, enabled: true)
    @label = label
    @log = log
    @UpdateOrder = order
    @Enabled = enabled
  end

  def Initialize = @log << ["initialize", @label]
  def Update(_game_time) = @log << ["update", @label]

  def UpdateOrder=(value)
    return if @UpdateOrder == value

    @UpdateOrder = value
    self.UpdateOrderChanged.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
  end
end

class CorpusDrawable < CorpusUpdateable
  extend CNA::Runtime::EventOwner
  include Microsoft::Xna::Framework::IDrawable

  xna_event :VisibleChanged
  xna_event :DrawOrderChanged

  attr_reader :Visible, :DrawOrder

  def initialize(label, log = [], order: 0, draw_order: 0, visible: true)
    super(label, log, order: order)
    @DrawOrder = draw_order
    @Visible = visible
  end

  def Draw(_game_time) = @log << ["draw", @label]

  def Visible=(value)
    return if @Visible == value

    @Visible = value
    self.VisibleChanged.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
  end
end

def corpus_labels(log, kind) = log.select { |entry| entry.first == kind }.map(&:last)

def error_name
  yield
  "none"
rescue Exception => error
  error.class.name
end

def equivalent?(actual, expected)
  if expected.instance_of?(Array)
    return actual.instance_of?(Array) && actual.length == expected.length && actual.zip(expected).all? { |left, right| equivalent?(left, right) }
  end
  return (actual.instance_of?(Integer) || actual.instance_of?(Float)) && (actual.to_f - expected).abs <= 1.0e-7 if expected.instance_of?(Float)

  actual == expected
end

def behavior_group(item)
  id = item.fetch("id")
  return "BOUNDING_BOX" if id.start_with?("box.")
  return "BOUNDING_SPHERE" if id.start_with?("sphere.")
  return "BOUNDING_FRUSTUM" if id.start_with?("frustum.")
  return "MATHHELPER" if id.start_with?("math.", "mathhelper.")
  return "VECTOR2" if id.start_with?("vector2.")
  return "VECTOR3" if id.start_with?("vector3.")
  return "VECTOR4" if id.start_with?("vector4.")
  return "QUATERNION" if id.start_with?("quaternion.")
  return "MATRIX" if id.start_with?("matrix.")
  return "PLANE" if id.start_with?("plane.")
  return "RAY" if id.start_with?("ray.")
  return "BINARY32" if id.start_with?("vector.scalar.", "float32.")
  return "CROSS_GEOMETRY" if id.start_with?("geometry.", "value.")
  return "CURVE_KEY_COLLECTION" if id.start_with?("curve.collection.")
  return "CURVE_EVALUATE" if id.start_with?("curve.evaluate.")
  return "CURVE_TANGENTS" if id.start_with?("curve.tangents.")
  return "CURVE_LOOPS" if id.start_with?("curve.loops.")
  return "CURVE_KEY" if id.start_with?("curve.key.")
  return "PACKED_ALPHA" if id.start_with?("packed.alpha.")
  return "PACKED_UNSIGNED" if id.start_with?("packed.unsigned.")
  return "PACKED_SIGNED" if id.start_with?("packed.signed.")
  return "PACKED_NORMALIZED" if id.start_with?("packed.normalized.")
  return "PACKED_HALF" if id.start_with?("packed.half.")
  return "PACKED_RGBA" if id.start_with?("packed.rgba.")
  return "PACKED_INTERFACE" if id.start_with?("packed.interface.")
  return "BUTTONS" if id.start_with?("buttons.")
  return "GAMEPAD_BUTTONS" if id.start_with?("gamepad_buttons.")
  return "GAMEPAD_DPAD" if id.start_with?("gamepad_dpad.")
  return "GAMEPAD_TRIGGERS" if id.start_with?("gamepad_triggers.")
  return "GAMEPAD_THUMBSTICKS" if id.start_with?("gamepad_thumbsticks.")
  return "GAMEPAD_STATE" if id.start_with?("gamepad_state.")
  return "GAMEPAD_ENUMS" if id.start_with?("gamepad_enums.")
  return "VERTEX_ELEMENT_ENUMS" if id.start_with?("vertex_element_enums.")
  return "VERTEX_ELEMENT" if id.start_with?("vertex_element.")
  return "DISPLAY_ORIENTATION" if id.start_with?("display_orientation.")
  return "GRAPHICS_DEVICE_STATUS" if id.start_with?("graphics_device_status.")
  return "GRAPHICS_PROFILE" if id.start_with?("graphics_profile.")
  return "VIEWPORT_PROJECT" if id.start_with?("viewport_project.")
  return "VIEWPORT_UNPROJECT" if id.start_with?("viewport_unproject.")
  return "VIEWPORT_TITLE_SAFE_AREA" if id.start_with?("viewport_title_safe_area.")
  return "CLEAR_OPTIONS" if id.start_with?("clear_options.")
  return "DEPTH_FORMAT" if id.start_with?("depth_format.")
  return "PRIMITIVE_TYPE" if id.start_with?("primitive_type.")
  return "PURE_MANAGED_ENUM_BATCH" if id.start_with?("pure_managed_enum.")
  return "TOUCH_CLOSURE" if id.start_with?("touch_closure.")
  return "INTERFACE_CONTRACT" if id.start_with?("interface_contract.")
  return "EVENT_PROJECTION" if id.start_with?("event_projection.")
  return "EVENT_RUNTIME" if id.start_with?("event_runtime.")
  return "BCL_PROJECTION" if id.start_with?("bcl_projection.")
  return "XNA_EXCEPTION" if id.start_with?("xna_exception.")
  return "IL_PROVENANCE" if id.start_with?("il_provenance.")
  return "TOUCH_VALUE" if id.start_with?("touch_value.")
  return "MANAGED_DESCRIPTOR" if id.start_with?("managed_descriptor.")
  return "CONSTRUCTOR_FREE" if id.start_with?("constructor_free.")
  return "CONTENT_ATTRIBUTE" if id.start_with?("content_attribute.")
  return "GAME_COMPONENT_COLLECTION" if id.start_with?("game_component_collection.")
  return "DISPOSABLE_COLLAPSE" if id.start_with?("disposable_collapse.")
  return "GAME_COMPONENTS" if id.start_with?("game_components.")
  return "GAME_COMPONENT" if id.start_with?("game_component.")

  id.split(".").first.upcase
end

def execute(item)
  args = item.fetch("args")
  case item.fetch("operation")
  when "Viewport.ProjectIdentity"
    viewport = qualified_viewport
    hex_values(vector3_result(viewport.Project(F::Vector3.new(-0.25, 0.5, 0.75),
                                               F::Matrix.Identity, F::Matrix.Identity, F::Matrix.Identity)))
  when "Viewport.ProjectDepth"
    viewport = qualified_viewport
    [0.0, 1.0, 0.3, 1.5].map do |depth|
      hex_values(vector3_result(viewport.Project(F::Vector3.new(0.125, -0.25, depth),
                                                 F::Matrix.Identity, F::Matrix.Identity, F::Matrix.Identity)))
    end
  when "Viewport.ProjectNontrivial"
    world, view, projection = viewport_matrices
    hex_values(vector3_result(qualified_viewport.Project(F::Vector3.new(0.375, -1.25, 2.5),
                                                         projection, view, world)))
  when "Viewport.ProjectWBoundary"
    viewport = G::Viewport.new(17, 23, 311, 197)
    source = F::Vector3.new(0.25, -0.375, 0.625)
    [0x3f800000, 0x3f7fffff, 0x3f800001, 0x40000000].map do |bits|
      hex_values(vector3_result(viewport.Project(source, F::Matrix.Identity, F::Matrix.Identity,
                                                 viewport_matrix_with_w(bits))))
    end
  when "Viewport.ProjectNegativeSpecial"
    viewport = G::Viewport.new(-31, 47, -257, -129)
    viewport.MinDepth = 0.8
    viewport.MaxDepth = -0.3
    ordinary = viewport.Project(F::Vector3.new(-0.6, 0.35, 1.25),
                                F::Matrix.Identity, F::Matrix.Identity, F::Matrix.Identity)
    special = qualified_viewport.Project(F::Vector3.new(Float::NAN, Float::INFINITY, -Float::INFINITY),
                                         F::Matrix.Identity, F::Matrix.Identity, F::Matrix.Identity)
    [hex_values(vector3_result(ordinary)), hex_values(vector3_result(special))]
  when "Viewport.UnprojectIdentity"
    result = qualified_viewport.Unproject(F::Vector3.new(253.375, 112.75, 0.6875),
                                          F::Matrix.Identity, F::Matrix.Identity, F::Matrix.Identity)
    hex_values(vector3_result(result))
  when "Viewport.UnprojectNontrivial"
    world, view, projection = viewport_matrices
    result = qualified_viewport.Unproject(F::Vector3.new(333.25, 211.5, 0.625), projection, view, world)
    hex_values(vector3_result(result))
  when "Viewport.UnprojectWBoundary"
    viewport = G::Viewport.new(17, 23, 311, 197)
    source = F::Vector3.new(211.375, 158.4375, 0.625)
    [0x3f800000, 0x3f7fffff, 0x3f800001, 0x3f000000].map do |bits|
      hex_values(vector3_result(viewport.Unproject(source, F::Matrix.Identity, F::Matrix.Identity,
                                                   viewport_matrix_with_w(bits))))
    end
  when "Viewport.UnprojectNegativeDegenerate"
    viewport = G::Viewport.new(-31, 47, -257, -129)
    viewport.MinDepth = 0.8
    viewport.MaxDepth = -0.3
    ordinary = viewport.Unproject(F::Vector3.new(-101.5, -11.25, 0.125),
                                  F::Matrix.Identity, F::Matrix.Identity, F::Matrix.Identity)
    zero = G::Viewport.new(5, -9, 0, 0)
    zero_result = zero.Unproject(F::Vector3.new(5, -9, 0.5),
                                 F::Matrix.Identity, F::Matrix.Identity, F::Matrix.Identity)
    zero.MinDepth = zero.MaxDepth = 0.25
    depth_result = zero.Unproject(F::Vector3.new(6, -8, 0.25),
                                  F::Matrix.Identity, F::Matrix.Identity, F::Matrix.Identity)
    singular_result = qualified_viewport.Unproject(F::Vector3.new(101, 77, 0.4), F::Matrix.new,
                                                    F::Matrix.Identity, F::Matrix.Identity)
    [hex_values(vector3_result(ordinary)), vector3_result(zero_result).map(&:nan?),
     vector3_result(depth_result).map(&:nan?), vector3_result(singular_result).map(&:nan?)]
  when "Viewport.RoundTrips"
    world, view, projection = viewport_matrices
    viewport = qualified_viewport
    object = F::Vector3.new(0.375, -1.25, 2.5)
    object_result = viewport.Unproject(viewport.Project(object, projection, view, world), projection, view, world)
    screen = F::Vector3.new(411.75, 83.125, 0.42)
    screen_result = viewport.Project(viewport.Unproject(screen, projection, view, world), projection, view, world)
    [hex_values(vector3_result(object_result)), hex_values(vector3_result(screen_result))]
  when "Viewport.TitleSafeArea"
    [[13, -7, 641, 479], [-11, 23, 5, 7], [3, 4, 0, 1], [7, -8, -9, -10]].map do |values|
      rectangle_result(G::Viewport.new(*values).TitleSafeArea)
    end
  when "Viewport.RubyMapping"
    viewport = qualified_viewport
    world, view, projection = viewport_matrices
    source = F::Vector3.new(0.375, -1.25, 2.5)
    before = [vector3_result(source), matrix_result(projection), matrix_result(view), matrix_result(world)]
    first = viewport.Project(source, projection, view, world)
    second = viewport.Project(source, projection, view, world)
    viewport.Unproject(first, projection, view, world)
    after = [vector3_result(source), matrix_result(projection), matrix_result(view), matrix_result(world)]
    first_title = viewport.TitleSafeArea
    second_title = viewport.TitleSafeArea
    first_title.X = -999
    [
      viewport.method(:Project).arity, viewport.method(:Unproject).arity,
      viewport.respond_to?(:TitleSafeArea=), viewport.respond_to?(:project), viewport.respond_to?(:unproject),
      viewport.respond_to?(:title_safe_area), G::GraphicsDevice.public_instance_methods(false).include?(:Viewport=),
      [error_name { viewport.Project([], projection, view, world) },
       error_name { viewport.Project(source, [], view, world) },
       error_name { viewport.Project(source, projection, [], world) },
       error_name { viewport.Project(source, projection, view, []) }],
      before == after, !first.equal?(second), rectangle_result(second_title) == [13, -7, 641, 479]
    ]
  when "ClearOptions.Contract"
    members = CLEAR_OPTIONS_SIGNATURE.fetch("members")
    [CLEAR_OPTIONS_SIGNATURE.fetch("kind"), CLEAR_OPTIONS_SIGNATURE.fetch("underlyingType"),
     CLEAR_OPTIONS_SIGNATURE.fetch("flags"),
     members.map { |member| [member.fetch("name"), Integer(member.fetch("value"))] },
     members.any? { |member| Integer(member.fetch("value")).zero? },
     members.any? { |member| member.fetch("name") == "All" }]
  when "ClearOptions.RubyFlagsMapping"
    options = G::ClearOptions
    named = [options::Target, options::DepthBuffer, options::Stencil]
    valid = (0..7).map { |raw| options.coerce(raw) }
    combinations = [
      options::Target | options::DepthBuffer,
      options::Target | options::Stencil,
      options::DepthBuffer | options::Stencil,
      options::Target | options::DepthBuffer | options::Stencil
    ]
    zero = options.coerce(0)
    intersection = options::Target & options::DepthBuffer
    foreign = [F::DisplayOrientation::LandscapeLeft, G::SpriteEffects::FlipHorizontally,
               I::Buttons::A, G::GraphicsDeviceStatus::Normal, G::GraphicsProfile::Reach,
               G::SurfaceFormat::Color]
    cross_flags = foreign.first(3)
    [
      named.all? { |value| value.instance_of?(options) },
      named.all?(&:frozen?),
      named.map(&:to_i),
      [options.coerce(1).equal?(options::Target), options.coerce(2).equal?(options::DepthBuffer),
       options.coerce(4).equal?(options::Stencil), options.coerce(options::Target).equal?(options::Target)],
      valid.map(&:to_i), valid.all? { |value| value.instance_of?(options) }, valid.all?(&:frozen?),
      valid.all? { |value| options.coerce(value.to_i).equal?(value) },
      [zero.instance_of?(options), zero.frozen?, zero.to_i, zero.to_s, zero.inspect,
       options.coerce(0).equal?(zero)],
      combinations.map(&:to_i), combinations.all? { |value| value.instance_of?(options) },
      combinations.all?(&:frozen?),
      [(combinations[0] & options::Target).equal?(options::Target),
       (combinations[1] & options::Stencil).equal?(options::Stencil),
       (combinations[3] & options::DepthBuffer).equal?(options::DepthBuffer)],
      [intersection.instance_of?(options), intersection.frozen?, intersection.equal?(zero),
       intersection.to_i, intersection.to_s],
      [8, 9, 0x100, -1].map { |raw| error_name { options.coerce(raw) } },
      [nil, true, false, 1.0, "1", Object.new].map { |value| error_name { options.coerce(value) } },
      foreign.map { |value| error_name { options.coerce(value) } },
      cross_flags.map { |value| error_name { options::Target | value } },
      cross_flags.map { |value| error_name { options::Target & value } },
      foreign.map { |value| options::Target == value },
      options.constants(false).map(&:to_s).sort,
      %i[None Default All value__].map { |name| options.constants(false).include?(name) },
      %i[ToString HasFlag Contains Includes Target? DepthBuffer? Stencil? None? All? Mask ValidBits]
        .map { |name| options::Target.respond_to?(name) },
      named.map(&:to_s), [zero, options.coerce(3), options.coerce(7)].map(&:to_s),
      [options::Target, zero, options.coerce(7)].map(&:inspect),
      [options::Target, zero, options.coerce(7)].map(&:to_i),
      options.instance_variable_get(:@enum_mask), G::GraphicsDevice.instance_method(:Clear).arity,
      G::GraphicsDevice.public_method_defined?(:Viewport=),
      CNA::Native::Manifest::CONSTANTS.keys.any? { |name| name.include?("CLEAR_OPTIONS") }
    ]
  when "DepthFormat.Contract"
    members = DEPTH_FORMAT_SIGNATURE.fetch("members")
    [DEPTH_FORMAT_SIGNATURE.fetch("kind"), DEPTH_FORMAT_SIGNATURE.fetch("underlyingType"),
     DEPTH_FORMAT_SIGNATURE.fetch("flags"),
     members.map { |member| [member.fetch("name"), Integer(member.fetch("value"))] },
     members.any? { |member| Integer(member.fetch("value")).zero? },
     members.any? { |member| member.fetch("name") == "Default" }]
  when "DepthFormat.RubyEnumMapping"
    format = G::DepthFormat
    values = [format::None, format::Depth16, format::Depth24, format::Depth24Stencil8]
    foreign = [G::SurfaceFormat::Color, G::GraphicsProfile::Reach, G::GraphicsDeviceStatus::Normal,
               G::ClearOptions::DepthBuffer, F::DisplayOrientation::Default,
               G::VertexElementFormat::Vector2, I::GamePadType::GamePad]
    [
      values.all? { |value| value.instance_of?(format) },
      values.all?(&:frozen?),
      values.map(&:to_i),
      (0..3).map { |raw| format.coerce(raw).equal?(values[raw]) },
      values.all? { |value| format.coerce(value).equal?(value) },
      [4, -1, 12_345, 2_147_483_647].map { |raw| error_name { format.coerce(raw) } },
      [nil, true, false, 1.0, "1", :Depth16, Object.new].map { |value| error_name { format.coerce(value) } },
      foreign.map { |value| error_name { format.coerce(value) } },
      foreign.map { |value| format::Depth24 == value },
      foreign.map { |value| format::Depth24 <=> value },
      [error_name { format::Depth16 | format::Depth24 },
       error_name { format::Depth24Stencil8 & format::Depth24 },
       error_name { format::None | format::Depth24Stencil8 }],
      format::Depth16.to_i | format::Depth24.to_i,
      format.instance_variable_get(:@enum_flags),
      format.instance_variable_get(:@enum_mask),
      values.map(&:to_s),
      values.map(&:inspect),
      format.constants(false).map(&:to_s).sort,
      %i[value__ Default Depth32 Stencil8].map { |name| format.constants(false).include?(name) },
      %i[ToString HasFlag HasStencil DepthBits StencilBits IsDepthOnly NativeFormat Parse]
        .map { |name| format::Depth24.respond_to?(name) },
      F::GraphicsDeviceManager.public_method_defined?(:PreferredDepthStencilFormat),
      # PresentationParameters arrived in Foundation 24 from its own IL, not from DepthFormat, so
      # this row asserts only the device and render-target surface DepthFormat still does not imply.
      %i[DepthStencilState RenderTarget2D RenderTargetCube GraphicsAdapter]
        .map { |name| G.const_defined?(name, false) },
      CNA::Native::Manifest::CONSTANTS.keys.any? { |name| name.include?("DEPTH_FORMAT") }
    ]
  when "InterfaceContract.Contract"
    clr_name = item.fetch("args").fetch(0)
    pinned = BATCH_REFERENCE.fetch(clr_name)
    members = pinned.fetch("members")
    [pinned.fetch("kind"), pinned["baseType"], pinned.fetch("directInterfaces"), members.length,
     members.map do |member|
       [member.fetch("name"), member.fetch("kind"), member["get"], member["set"],
        member.fetch("parameters", []).length]
     end,
     members.count { |member| member.fetch("kind") == "event" }]
  when "InterfaceContract.RubyMapping"
    clr_name = item.fetch("args").fetch(0)
    short = clr_name.split(".").last
    interface = batch_enum_type(clr_name)
    projections = interface.public_instance_methods(false).map(&:to_s).sort
    host = Class.new { include(interface) }
    errors = projections.map { |name| error_name { invoke_projection(host.new, name) } }
    messages = projections.map do |name|
      begin
        invoke_projection(host.new, name)
        "none"
      rescue Exception => error
        error.message
      end
    end
    [
      interface.instance_of?(Module),
      interface.instance_of?(Class),
      projections,
      errors,
      messages,
      interface.constants(false),
      interface.protected_instance_methods(false) + interface.private_instance_methods(false),
      BATCH_SIGNATURES.fetch(clr_name).fetch("members").any? { |member| member.fetch("kind") == "event" }
    ]
  when "ContentAttribute.Defaults"
    attribute = CONTENT::ContentSerializerAttribute.new
    [attribute.ElementName, attribute.FlattenContent, attribute.Optional, attribute.AllowNull,
     attribute.SharedResource, attribute.CollectionItemName, attribute.HasCollectionItemName,
     CONTENT::ContentSerializerAttribute.superclass.name,
     CONTENT::ContentSerializerAttribute.public_instance_methods(false).map(&:to_s).sort]
  when "ContentAttribute.Validation"
    attribute = CONTENT::ContentSerializerAttribute.new
    messages = ->(block) do
      begin
        block.call
        "none"
      rescue Exception => error
        "#{error.class}:#{error.message}"
      end
    end
    [messages.call(-> { attribute.CollectionItemName = "" }),
     messages.call(-> { attribute.CollectionItemName = nil }),
     error_name { attribute.CollectionItemName = 5 },
     attribute.CollectionItemName,
     error_name { attribute.ElementName = "" }, error_name { attribute.ElementName = nil },
     %i[FlattenContent= Optional= AllowNull= SharedResource=].map do |setter|
       error_name { attribute.public_send(setter, 1) }
     end,
     messages.call(-> { CONTENT::ContentSerializerCollectionItemNameAttribute.new("") }),
     messages.call(-> { CONTENT::ContentSerializerRuntimeTypeAttribute.new("") }),
     error_name { CONTENT::ContentSerializerTypeVersionAttribute.new(2**31) },
     error_name { CONTENT::ContentSerializerTypeVersionAttribute.new(-3) }]
  when "ContentAttribute.Clone"
    attribute = CONTENT::ContentSerializerAttribute.new
    attribute.ElementName = "Node"
    attribute.FlattenContent = true
    attribute.Optional = true
    attribute.AllowNull = false
    attribute.SharedResource = true
    attribute.CollectionItemName = "Entry"
    copy = attribute.Clone
    fresh = CONTENT::ContentSerializerAttribute.new.Clone
    [copy.equal?(attribute),
     [copy.ElementName, copy.FlattenContent, copy.Optional, copy.AllowNull, copy.SharedResource,
      copy.CollectionItemName, copy.HasCollectionItemName],
     [fresh.CollectionItemName, fresh.HasCollectionItemName, fresh.AllowNull]]
  when "ContentAttribute.SingleArgument"
    [CONTENT::ContentSerializerCollectionItemNameAttribute.new("Entry").CollectionItemName,
     CONTENT::ContentSerializerRuntimeTypeAttribute.new("Foo").RuntimeType,
     CONTENT::ContentSerializerTypeVersionAttribute.new(3).TypeVersion,
     CONTENT::ContentSerializerTypeVersionAttribute.new(-3).TypeVersion,
     CONTENT::ContentSerializerIgnoreAttribute.new.instance_of?(CONTENT::ContentSerializerIgnoreAttribute),
     CONTENT::ContentSerializerIgnoreAttribute.public_instance_methods(false).map(&:to_s),
     CONTENT.constants(false).map(&:to_s).sort,
     CNA::Runtime::Attribute.public_instance_methods(false).map(&:to_s),
     CNA::Runtime::Attribute.superclass.name]
  when "DisplayModeCollection.Projection"
    build = ->(width, height, format) { G::DisplayMode.__send__(:new, width, height, format) }
    modes = [build.call(1920, 1080, G::SurfaceFormat::Color),
             build.call(800, 600, G::SurfaceFormat::Bgra4444),
             build.call(1280, 720, G::SurfaceFormat::Color)]
    collection = G::DisplayModeCollection.__send__(:new, modes)
    empty = G::DisplayModeCollection.__send__(:new, [])
    source = [build.call(640, 480, G::SurfaceFormat::Color)]
    copied = G::DisplayModeCollection.__send__(:new, source)
    source << build.call(1024, 768, G::SurfaceFormat::Color)
    [collection.GetEnumerator.to_a.map(&:Width),
     collection.GetEnumerator.equal?(collection.GetEnumerator),
     collection.GetEnumerator.instance_of?(Enumerator),
     collection[G::SurfaceFormat::Color].to_a.map(&:Width),
     collection[G::SurfaceFormat::Bgra4444].to_a.map(&:Width),
     collection[G::SurfaceFormat::Alpha8].to_a,
     empty.GetEnumerator.to_a, copied.GetEnumerator.to_a.length,
     G::DisplayModeCollection.respond_to?(:new),
     G::DisplayModeCollection.public_instance_methods(false).map(&:to_s).sort,
     G::DisplayModeCollection.ancestors.include?(Enumerable),
     error_name { collection[9999] },
     error_name { G::DisplayModeCollection.__send__(:new, [1]) }]
  when "ConstructorFree.Projection"
    names = item.fetch("args")
    names.map do |clr_name|
      runtime = batch_enum_type(clr_name)
      entry = IL_INVENTORY.fetch("types").fetch(clr_name)
      [clr_name, runtime.respond_to?(:new), runtime.respond_to?(:new, true),
       error_name { runtime.new }, entry.fetch("constructors").map { |ctor| ctor.fetch("access") },
       BATCH_SIGNATURES.fetch(clr_name).fetch("members").any? { |member| member.fetch("kind") == "constructor" }]
    end
  when "DisplayMode.Projection"
    build = ->(width, height) { G::DisplayMode.__send__(:new, width, height, G::SurfaceFormat::Color) }
    mode = build.call(1920, 1080)
    [mode.Width, mode.Height, mode.Format.to_s,
     rectangle_result(mode.TitleSafeArea), mode.TitleSafeArea.equal?(mode.TitleSafeArea),
     [[1920, 1080], [1024, 768], [0, 1080], [1920, 0], [0, 0], [-4, 2]].map do |width, height|
       hex32(build.call(width, height).AspectRatio)
     end,
     mode.ToString, build.call(0, 0).ToString, mode.to_s == mode.ToString,
     G::DisplayMode.public_instance_methods(false).map(&:to_s).sort]
  when "ResourceEventArgs.Projection"
    created = G::ResourceCreatedEventArgs.__send__(:new, :the_resource)
    destroyed = G::ResourceDestroyedEventArgs.__send__(:new, "surface", :the_tag)
    empty = G::ResourceDestroyedEventArgs.__send__(:new, nil, nil)
    [created.Resource.to_s, created.is_a?(CNA::Runtime::EventArgs),
     G::ResourceCreatedEventArgs.superclass.name,
     destroyed.Name, destroyed.Tag.to_s, destroyed.is_a?(CNA::Runtime::EventArgs),
     empty.Name.nil?, empty.Tag.nil?,
     G::ResourceCreatedEventArgs.public_instance_methods(false).map(&:to_s).sort,
     G::ResourceDestroyedEventArgs.public_instance_methods(false).map(&:to_s).sort]
  when "ManagedDescriptor.IlContract"
    clr_name = item.fetch("args").fetch(0)
    entry = IL_INVENTORY.fetch("types").fetch(clr_name)
    pinned = BATCH_REFERENCE.fetch(clr_name)
    [pinned.fetch("kind"), pinned.fetch("baseType"), pinned.fetch("members").length,
     entry.fetch("assembly"), entry.fetch("assemblySha256"),
     entry.fetch("declaredFields"), entry.fetch("nativeReachable"), entry.fetch("declaresNativeEntryPoint"),
     entry.fetch("constructors").map { |ctor| [ctor.fetch("access"), ctor.fetch("pureBaseForward")] }]
  when "XactSpatial.Defaults"
    A::AudioListener.new.then do |listener|
      A::AudioEmitter.new.then do |emitter|
        [listener, emitter].flat_map do |value|
          [vector3_result(value.Position), format("%08x", CNA::Runtime::Numeric.f32_bits(value.Position.Z)),
           vector3_result(value.Velocity), format("%08x", CNA::Runtime::Numeric.f32_bits(value.Velocity.Z)),
           vector3_result(value.Forward), format("%08x", CNA::Runtime::Numeric.f32_bits(value.Forward.Z)),
           vector3_result(value.Up), format("%08x", CNA::Runtime::Numeric.f32_bits(value.Up.Z))]
        end
      end
    end
  when "XactSpatial.RoundTrip"
    source = F::Vector3.new(1.5, -2.25, 3.75)
    [A::AudioListener.new, A::AudioEmitter.new].flat_map do |value|
      %i[Position Velocity Forward Up].flat_map do |name|
        value.public_send(:"#{name}=", source)
        [vector3_result(value.public_send(name)),
         value.public_send(name).equal?(value.public_send(name)),
         error_name { value.public_send(:"#{name}=", :not_a_vector) }]
      end
    end
  when "XactSpatial.DopplerScale"
    emitter = A::AudioEmitter.new
    initial = emitter.DopplerScale
    accepted = [0.0, -0.0, 1.5, Float::INFINITY].map do |candidate|
      emitter.DopplerScale = candidate
      hex32(emitter.DopplerScale)
    end
    emitter.DopplerScale = Float::NAN
    nan_accepted = emitter.DopplerScale.nan?
    rejected = [-1.0, -Float::INFINITY].map { |candidate| error_name { emitter.DopplerScale = candidate } }
    [initial, accepted, nan_accepted, rejected, emitter.DopplerScale.nan?,
     A::AudioEmitter.public_instance_methods(false).map(&:to_s).sort,
     %w[ChannelCount ChannelRadius CurveDistanceScaler].map { |name| A::AudioEmitter.method_defined?(name) }]
  when "PresentationParameters.Defaults"
    parameters = G::PresentationParameters.new
    [parameters.BackBufferWidth, parameters.BackBufferHeight,
     parameters.BackBufferFormat.to_s, parameters.DepthStencilFormat.to_s,
     parameters.MultiSampleCount, parameters.DisplayOrientation.to_s,
     parameters.PresentationInterval.to_s, parameters.RenderTargetUsage.to_s,
     parameters.DeviceWindowHandle, parameters.IsFullScreen,
     rectangle_result(parameters.Bounds), parameters.Bounds.equal?(parameters.Bounds)]
  when "PresentationParameters.Mutation"
    parameters = G::PresentationParameters.new
    parameters.BackBufferWidth = -5
    parameters.BackBufferHeight = -7
    parameters.MultiSampleCount = -1
    parameters.DeviceWindowHandle = -1
    parameters.IsFullScreen = false
    [parameters.BackBufferWidth, parameters.BackBufferHeight, parameters.MultiSampleCount,
     parameters.DeviceWindowHandle, parameters.IsFullScreen, rectangle_result(parameters.Bounds),
     error_name { parameters.BackBufferWidth = 2**31 },
     error_name { parameters.BackBufferFormat = 9999 },
     error_name { parameters.IsFullScreen = 1 },
     error_name { parameters.DeviceWindowHandle = 2**(CNA::Runtime::Numeric.pointer_width_bits - 1) }]
  when "PresentationParameters.Clone"
    parameters = G::PresentationParameters.new
    parameters.BackBufferWidth = 800
    parameters.BackBufferHeight = 600
    parameters.BackBufferFormat = G::SurfaceFormat::Bgra4444
    parameters.DepthStencilFormat = G::DepthFormat::Depth24Stencil8
    parameters.MultiSampleCount = 4
    parameters.DisplayOrientation = F::DisplayOrientation::LandscapeLeft
    parameters.PresentationInterval = G::PresentInterval::Two
    parameters.RenderTargetUsage = G::RenderTargetUsage::PreserveContents
    parameters.DeviceWindowHandle = 4242
    parameters.IsFullScreen = false
    copy = parameters.Clone
    copy.BackBufferWidth = 1
    [copy.equal?(parameters), copy.instance_of?(G::PresentationParameters),
     [copy.BackBufferHeight, copy.BackBufferFormat.to_s, copy.DepthStencilFormat.to_s,
      copy.MultiSampleCount, copy.DisplayOrientation.to_s, copy.PresentationInterval.to_s,
      copy.RenderTargetUsage.to_s, copy.DeviceWindowHandle, copy.IsFullScreen],
     parameters.BackBufferWidth, copy.BackBufferWidth]
  when "GameComponentCollectionEventArgs.Storage"
    host = Class.new { include F::IGameComponent }
    component = host.new
    args = F::GameComponentCollectionEventArgs.new(component)
    [args.GameComponent.equal?(component),
     F::GameComponentCollectionEventArgs.superclass.name,
     args.is_a?(CNA::Runtime::EventArgs),
     F::GameComponentCollectionEventArgs.new(nil).GameComponent.nil?,
     error_name { F::GameComponentCollectionEventArgs.new(5) },
     error_name { F::GameComponentCollectionEventArgs.new },
     F::GameComponentCollectionEventArgs.public_instance_methods(false).map(&:to_s).sort]
  when "TouchValue.IlContract"
    clr_name = item.fetch("args").fetch(0)
    entry = IL_INVENTORY.fetch("types").fetch(clr_name)
    pinned = BATCH_REFERENCE.fetch(clr_name)
    [pinned.fetch("kind"), pinned.fetch("sealed"), pinned.fetch("baseType"),
     pinned.fetch("directInterfaces"), pinned.fetch("members").length,
     entry.fetch("assembly"), entry.fetch("assemblySha256"),
     entry.fetch("declaredFields"), entry.fetch("nativeReachable"),
     entry.fetch("constructors").map { |ctor| [ctor.fetch("access"), ctor.fetch("pureBaseForward")] }]
  when "GameServiceContainer.Contract"
    services = F::GameServiceContainer.new
    contract = Module.new
    provider = Object.new
    provider.extend(contract)
    unrelated = Module.new
    guard = lambda do |operation|
      operation.call
      "no-raise"
    rescue StandardError => error
      [error.class.name, error.message]
    end
    before = services.GetService(contract)
    services.AddService(contract, provider)
    [before.nil?, services.GetService(contract).equal?(provider),
     guard.call(-> { services.AddService(contract, provider) }),
     guard.call(-> { services.AddService(nil, provider) }),
     guard.call(-> { services.AddService(contract.class, nil) }),
     guard.call(-> { services.AddService(unrelated, provider) }),
     guard.call(-> { services.GetService(nil) }),
     services.GetService(unrelated).nil?,
     services.RemoveService(contract).nil?, services.GetService(contract).nil?,
     services.RemoveService(contract).nil?,
     F::GameServiceContainer.new.GetService(contract).nil?]
  when "TouchPanel.StubContract"
    capabilities = TOUCH::TouchPanel.GetCapabilities
    state = TOUCH::TouchPanel.GetState
    touch_types = IL_INVENTORY.fetch("types").select do |_name, entry|
      entry.fetch("assembly") == "Microsoft.Xna.Framework.Input.Touch.dll"
    end
    [capabilities.IsConnected, capabilities.MaximumTouchCount,
     state.class.name.split("::").last, state.Count, state.IsConnected, state.IsReadOnly,
     touch_types.length, touch_types.values.map { |entry| entry.fetch("nativeReachable") }.uniq,
     touch_types.values.map { |entry| entry.fetch("nativeReachableMethods") }.flatten]
  when "TouchPanel.Gestures"
    saved = %i[@enabled_gestures @gestures_have_been_enabled].to_h do |name|
      [name, TOUCH::TouchPanel.instance_variable_get(name)]
    end
    begin
      TOUCH::TouchPanel.instance_variable_set(:@enabled_gestures, nil)
      TOUCH::TouchPanel.instance_variable_set(:@gestures_have_been_enabled, nil)
      guard = lambda do |operation|
        operation.call
        "no-raise"
      rescue StandardError => error
        error.class.name
      end
      before = [TOUCH::TouchPanel.EnabledGestures.name,
                guard.call(-> { TOUCH::TouchPanel.IsGestureAvailable }),
                guard.call(-> { TOUCH::TouchPanel.ReadGesture })]
      TOUCH::TouchPanel.EnabledGestures = TOUCH::GestureType::Tap
      after = [TOUCH::TouchPanel.EnabledGestures.name, TOUCH::TouchPanel.IsGestureAvailable,
               guard.call(-> { TOUCH::TouchPanel.ReadGesture })]
      declared = TOUCH::GestureType.constants(false)
                                   .map { |name| TOUCH::GestureType.const_get(name, false).value }
                                   .reduce(0) { |mask, value| mask | value }
      [before, after, declared, guard.call(-> { TOUCH::TouchPanel.EnabledGestures = 0x400 })]
    ensure
      saved.each { |name, value| TOUCH::TouchPanel.instance_variable_set(name, value) }
    end
  when "TouchPanel.DisplaySettings"
    saved = %i[@window_handle @display_orientation @display_width @display_height].to_h do |name|
      [name, TOUCH::TouchPanel.instance_variable_get(name)]
    end
    begin
      guard = lambda do |operation|
        operation.call
        "no-raise"
      rescue StandardError => error
        error.class.name
      end
      TOUCH::TouchPanel.WindowHandle = 0x1234
      TOUCH::TouchPanel.DisplayWidth = 480
      TOUCH::TouchPanel.DisplayHeight = 800
      TOUCH::TouchPanel.DisplayOrientation = F::DisplayOrientation::Portrait
      combined = F::DisplayOrientation::LandscapeLeft | F::DisplayOrientation::Portrait
      [TOUCH::TouchPanel.WindowHandle, TOUCH::TouchPanel.DisplayWidth,
       TOUCH::TouchPanel.DisplayHeight, TOUCH::TouchPanel.DisplayOrientation.name,
       guard.call(-> { TOUCH::TouchPanel.DisplayOrientation = combined }),
       TOUCH::TouchPanel.DisplayOrientation.name,
       guard.call(-> { TOUCH::TouchPanel.DisplayWidth = 1.5 })]
    ensure
      saved.each { |name, value| TOUCH::TouchPanel.instance_variable_set(name, value) }
    end
  when "TouchCollection.Contract"
    locations = [TOUCH::TouchLocation.new(1, TOUCH::TouchLocationState::Pressed, F::Vector2.new(1.0, 2.0)),
                 TOUCH::TouchLocation.new(2, TOUCH::TouchLocationState::Moved, F::Vector2.new(3.0, 4.0),
                                          TOUCH::TouchLocationState::Pressed, F::Vector2.new(0.5, 0.25))]
    touches = TOUCH::TouchCollection.new(locations)
    empty = TOUCH::TouchCollection.new([])
    [touches.Count, touches.IsConnected, touches.IsReadOnly,
     touches[0].Id, touches[1].Id, touches[1].State.name,
     touches[1].TryGetPreviousLocation.first, touches[1].TryGetPreviousLocation.last.State.name,
     touches[0].TryGetPreviousLocation.first, touches[0].TryGetPreviousLocation.last.State.name,
     empty.Count, empty.IsConnected, empty.IsReadOnly]
  when "TouchCollection.Ceiling"
    build = lambda do |count|
      TOUCH::TouchCollection.new(Array.new(count) do |index|
        TOUCH::TouchLocation.new(index, TOUCH::TouchLocationState::Pressed, F::Vector2.new(0.0, 0.0))
      end).Count
    rescue StandardError => error
      [error.class.name, error.message]
    end
    [build.call(0), build.call(7), build.call(8), build.call(9),
     (begin
        TOUCH::TouchCollection.new(nil)
      rescue StandardError => error
        [error.class.name, error.message]
      end)]
  when "TouchCollection.Bounds"
    touches = TOUCH::TouchCollection.new([
      TOUCH::TouchLocation.new(1, TOUCH::TouchLocationState::Pressed, F::Vector2.new(1.0, 2.0))
    ])
    read = lambda do |index|
      touches[index].Id
    rescue StandardError => error
      [error.class.name, error.message]
    end
    [read.call(0), read.call(-1), read.call(1), read.call(8), read.call(nil)]
  when "TouchCollection.ReadOnly"
    touches = TOUCH::TouchCollection.new([
      TOUCH::TouchLocation.new(1, TOUCH::TouchLocationState::Pressed, F::Vector2.new(1.0, 2.0))
    ])
    item = touches[0]
    refusals = [-> { touches.Add(item) }, -> { touches.Clear }, -> { touches.Insert(0, item) },
                -> { touches.Remove(item) }, -> { touches.RemoveAt(0) }, -> { touches[0] = item }]
    classes = refusals.map do |mutation|
      mutation.call
      "no-raise"
    rescue StandardError => error
      error.class.name
    end
    [touches.IsReadOnly, classes, touches.Count,
     CNA::Runtime::NotSupportedError < StandardError,
     CNA::Runtime::NotSupportedError.ancestors.include?(ScriptError)]
  when "TouchCollection.Search"
    touches = TOUCH::TouchCollection.new([
      TOUCH::TouchLocation.new(5, TOUCH::TouchLocationState::Pressed, F::Vector2.new(1.0, 2.0)),
      TOUCH::TouchLocation.new(9, TOUCH::TouchLocationState::Moved, F::Vector2.new(3.0, 4.0))
    ])
    differing = TOUCH::TouchLocation.new(5, TOUCH::TouchLocationState::Moved, F::Vector2.new(1.0, 2.0))
    found, located = touches.FindById(9)
    missing, default = touches.FindById(1234)
    [touches.IndexOf(touches[0]), touches.IndexOf(touches[1]),
     touches.IndexOf(TOUCH::TouchLocation.new(77, TOUCH::TouchLocationState::Pressed, F::Vector2.new(0.0, 0.0))),
     differing.Equals(touches[0]), touches.IndexOf(differing),
     touches.Contains(touches[1]), touches.Contains(differing),
     found, located.Id, missing, default.Id, default.State.name, vector_result(default.Position)]
  when "TouchCollection.CopyTo"
    touches = TOUCH::TouchCollection.new([
      TOUCH::TouchLocation.new(1, TOUCH::TouchLocationState::Pressed, F::Vector2.new(1.0, 2.0)),
      TOUCH::TouchLocation.new(2, TOUCH::TouchLocationState::Pressed, F::Vector2.new(3.0, 4.0))
    ])
    destination = Array.new(4)
    touches.CopyTo(destination, 1)
    guard = lambda do |array, index|
      touches.CopyTo(array, index)
      "no-raise"
    rescue StandardError => error
      [error.class.name, error.message]
    end
    [destination.map { |value| value.nil? ? nil : value.Id },
     guard.call(nil, 0), guard.call(destination, -1), guard.call(Array.new(2), 1), guard.call(Array.new(2), 0)]
  when "TouchCollection.Enumeration"
    touches = TOUCH::TouchCollection.new([
      TOUCH::TouchLocation.new(1, TOUCH::TouchLocationState::Pressed, F::Vector2.new(1.0, 2.0)),
      TOUCH::TouchLocation.new(2, TOUCH::TouchLocationState::Moved, F::Vector2.new(3.0, 4.0))
    ])
    enumerator = touches.GetEnumerator
    before = begin
      enumerator.Current
      "no-raise"
    rescue StandardError => error
      [error.class.name, error.message]
    end
    walked = []
    walked << enumerator.Current.Id while enumerator.MoveNext
    after = begin
      enumerator.Current
      "no-raise"
    rescue StandardError => error
      [error.class.name, error.message]
    end
    [enumerator.class.name.split("::").last, before, walked, enumerator.MoveNext, after,
     enumerator.Dispose.nil?, touches.GetEnumerator.equal?(touches.GetEnumerator),
     TOUCH::TouchCollection.new([]).GetEnumerator.MoveNext,
     touches.map(&:Id), touches.each.to_a.length]
  when "TouchLocation.Construction"
    plain = TOUCH::TouchLocation.new(3, TOUCH::TouchLocationState::Moved, F::Vector2.new(1.5, -2.25))
    chained = TOUCH::TouchLocation.new(3, TOUCH::TouchLocationState::Moved, F::Vector2.new(1.5, -2.25),
                                       TOUCH::TouchLocationState::Pressed, F::Vector2.new(0.5, 0.25))
    [plain.Id, plain.State.to_s, vector_result(plain.Position),
     chained.Id, chained.State.to_s, vector_result(chained.Position),
     plain.Position.equal?(plain.Position),
     error_name { TOUCH::TouchLocation.new(1, TOUCH::TouchLocationState::Moved) },
     error_name { TOUCH::TouchLocation.new(1, TOUCH::TouchLocationState::Moved, 5) },
     error_name { TOUCH::TouchLocation.new(2**31, TOUCH::TouchLocationState::Moved, F::Vector2.new(0, 0)) }]
  when "TouchLocation.PreviousLocation"
    plain = TOUCH::TouchLocation.new(3, TOUCH::TouchLocationState::Moved, F::Vector2.new(1.5, -2.25))
    chained = TOUCH::TouchLocation.new(3, TOUCH::TouchLocationState::Moved, F::Vector2.new(1.5, -2.25),
                                       TOUCH::TouchLocationState::Pressed, F::Vector2.new(0.5, 0.25))
    empty_found, empty = plain.TryGetPreviousLocation
    found, previous = chained.TryGetPreviousLocation
    [empty_found, empty.Id, empty.State.to_s, vector_result(empty.Position),
     found, previous.Id, previous.State.to_s, vector_result(previous.Position),
     previous.TryGetPreviousLocation.first,
     %w[Invalid Released Pressed Moved].map do |state|
       TOUCH::TouchLocation.new(1, TOUCH::TouchLocationState::Moved, F::Vector2.new(0, 0),
                                TOUCH::TouchLocationState.const_get(state), F::Vector2.new(1, 1))
                           .TryGetPreviousLocation.first
     end]
  when "TouchLocation.Equality"
    base = TOUCH::TouchLocation.new(3, TOUCH::TouchLocationState::Moved, F::Vector2.new(1.5, -2.25))
    other_state = TOUCH::TouchLocation.new(3, TOUCH::TouchLocationState::Released, F::Vector2.new(1.5, -2.25))
    other_id = TOUCH::TouchLocation.new(4, TOUCH::TouchLocationState::Moved, F::Vector2.new(1.5, -2.25))
    other_x = TOUCH::TouchLocation.new(3, TOUCH::TouchLocationState::Moved, F::Vector2.new(9.0, -2.25))
    prev_a = TOUCH::TouchLocation.new(3, TOUCH::TouchLocationState::Moved, F::Vector2.new(1.5, -2.25),
                                      TOUCH::TouchLocationState::Pressed, F::Vector2.new(0.5, 0.25))
    prev_b = TOUCH::TouchLocation.new(3, TOUCH::TouchLocationState::Moved, F::Vector2.new(1.5, -2.25),
                                      TOUCH::TouchLocationState::Released, F::Vector2.new(0.5, 0.25))
    nan = TOUCH::TouchLocation.new(1, TOUCH::TouchLocationState::Pressed, F::Vector2.new(Float::NAN, 0.0))
    # Equals ignores state and prevState; op_Equality compares all seven fields.
    [base.Equals(other_state), base == other_state,
     prev_a.Equals(prev_b), prev_a == prev_b,
     base.Equals(other_id), base == other_id,
     base.Equals(other_x), base == other_x,
     base.Equals(prev_a), base == prev_a,
     base.Equals(:not_a_location), base == :not_a_location,
     base == base.dup, base != base.dup, base != other_id,
     nan == nan.dup, nan.Equals(nan.dup)]
  when "TouchLocation.HashString"
    base = TOUCH::TouchLocation.new(3, TOUCH::TouchLocationState::Moved, F::Vector2.new(1.5, -2.25))
    chained = TOUCH::TouchLocation.new(3, TOUCH::TouchLocationState::Moved, F::Vector2.new(1.5, -2.25),
                                       TOUCH::TouchLocationState::Pressed, F::Vector2.new(0.5, 0.25))
    [base.GetHashCode, chained.GetHashCode,
     TOUCH::TouchLocation.new(3, TOUCH::TouchLocationState::Released, F::Vector2.new(1.5, -2.25)).GetHashCode,
     TOUCH::TouchLocation.new(4, TOUCH::TouchLocationState::Moved, F::Vector2.new(1.5, -2.25)).GetHashCode,
     TOUCH::TouchLocation.new(0, TOUCH::TouchLocationState::Invalid, F::Vector2.new(0.0, -0.0)).GetHashCode,
     base.ToString, chained.ToString, base.to_s == base.ToString]
  when "GestureSample.Storage"
    shared = F::Vector2.new(1, 2)
    sample = TOUCH::GestureSample.new(TOUCH::GestureType::Tap | TOUCH::GestureType::Hold, 1.25,
                                      F::Vector2.new(1, 2), F::Vector2.new(3, 4),
                                      F::Vector2.new(5, 6), F::Vector2.new(7, 8))
    copies = TOUCH::GestureSample.new(TOUCH::GestureType::Tap, 0.0, shared, shared, shared, shared)
    [sample.GestureType.to_i, sample.Timestamp,
     vector_result(sample.Position), vector_result(sample.Position2),
     vector_result(sample.Delta), vector_result(sample.Delta2),
     copies.Position.equal?(copies.Position), copies.Position.equal?(copies.Position2),
     TOUCH::GestureSample.public_instance_methods(false).map(&:to_s).sort,
     error_name { TOUCH::GestureSample.new(TOUCH::GestureType::Tap, "x", shared, shared, shared, shared) },
     error_name { TOUCH::GestureSample.new(TOUCH::GestureType::Tap, 0.0, 1, 2, 3, 4) },
     error_name { TOUCH::GestureSample.new(TOUCH::GestureType::Tap, 0.0) }]
  when "BclProjection.TimeSpan"
    register = CNA::Runtime::BclProjection
    [register::TYPES.fetch("System.TimeSpan"),
     register.time_span(1.25), register.time_span(2).instance_of?(Float),
     error_name { register.time_span("1.25") }, error_name { register.time_span(nil) },
     F::GameTime.new(1.5, 0.25).TotalGameTime, F::GameTime.new(1.5, 0.25).ElapsedGameTime]
  when "XnaException.IlContract"
    clr_name = item.fetch("args").fetch(0)
    entry = IL_INVENTORY.fetch("types").fetch(clr_name)
    pinned = BATCH_REFERENCE.fetch(clr_name)
    [pinned.fetch("kind"), pinned.fetch("sealed"), pinned.fetch("baseType"),
     entry.fetch("declaredFields"), entry.fetch("declaredMethods"),
     entry.fetch("nativeReachable"),
     entry.fetch("constructors").map do |ctor|
       [ctor.fetch("access"), ctor.fetch("leadingArgumentLoads"), ctor.fetch("pureBaseForward")]
     end,
     entry.fetch("assemblySha256")]
  when "XnaException.RubyMapping"
    clr_name = item.fetch("args").fetch(0)
    klass = batch_enum_type(clr_name)
    inner = ArgumentError.new("inner")
    plain = klass.new
    message = klass.new("m")
    chained = klass.new("m", inner)
    rescued = begin
      raise klass, "raised"
    rescue StandardError => error
      [error.class.name, error.message]
    end
    [
      klass.instance_of?(Class), klass.superclass.name, (klass <= StandardError),
      klass.public_instance_methods(false), klass.constants(false),
      plain.message, message.message, chained.message,
      plain.cause.nil?, chained.cause.equal?(inner), chained.backtrace.nil?,
      klass.new("m", nil).cause.nil?, klass.new(nil).message,
      rescued, error_name { klass.new("m", 42) }
    ]
  when "IlProvenance.Assemblies"
    [IL_INVENTORY.fetch("assemblies").length,
     IL_INVENTORY.fetch("assemblies").map { |assembly| [assembly.fetch("name"), assembly.fetch("version"), assembly.fetch("sha256")] },
     IL_INVENTORY.fetch("REFERENCE_TYPES"), IL_INVENTORY.fetch("TYPES_WITH_IL"),
     IL_INVENTORY.fetch("TYPES_NATIVE_REACHABLE")]
  when "IlProvenance.NativeBoundary"
    names = item.fetch("args")
    names.map { |name| [name, IL_INVENTORY.fetch("types").fetch(name).fetch("nativeReachable")] }
  when "BclProjection.Register"
    # Each milestone pins the identities it established rather than a whole-register snapshot, so
    # a later milestone adding an entry never rewrites an earlier row.
    register = CNA::Runtime::BclProjection
    identities = item.fetch("args")
    [identities.map do |identity|
       [identity, register.ruby_type(identity), register.exception_base?(identity),
        register::TYPES.key?(identity)]
     end,
     Object.const_defined?(:System, false)]
  when "BclProjection.ExceptionBaseRule"
    roots = CNA::Runtime::BclProjection::EXCEPTION_BASES.values.uniq
    resolved = roots.map { |root| Object.const_get(root, false) }
    rescued = begin
      raise StandardError, "projected"
    rescue StandardError => error
      error.message
    end
    [roots, resolved.map { |root| root.instance_of?(Class) },
     resolved.map { |root| root <= StandardError }, resolved.map { |root| root <= ::Exception },
     resolved.map { |root| root.equal?(::Exception) }, resolved.map(&:name), rescued,
     CNA::Runtime.const_defined?(:XnaException, false),
     CNA::Runtime.const_defined?(:ExternalException, false)]
  when "BclProjection.ExceptionContract"
    clr_name = item.fetch("args").fetch(0)
    pinned = BATCH_REFERENCE.fetch(clr_name)
    # Pinned XNA facts only. Whether the binding has selected the type is a mapping fact and
    # belongs in a RUBY_MAPPING_QUALIFICATION row, not here.
    [pinned.fetch("kind"), pinned.fetch("sealed"), pinned.fetch("baseType"),
     pinned.fetch("directInterfaces"), pinned.fetch("members").length,
     pinned.fetch("members").map do |member|
       [member.fetch("kind"), member.fetch("access"),
        member.fetch("parameters").map { |parameter| parameter.fetch("type") }]
     end]
  when "BclProjection.ExceptionDeferral"
    names = BATCH_REFERENCE.keys.grep(/Exception\z/).sort
    [names.length, names,
     names.map do |name|
       BATCH_REFERENCE.fetch(name).fetch("members").all? { |member| member.fetch("kind") == "constructor" }
     end,
     names.map do |name|
       BATCH_REFERENCE.fetch(name).fetch("members").any? do |member|
         member.fetch("parameters").any? { |parameter| parameter.fetch("type").include?("SerializationInfo") }
       end
     end]
  when "EventProjection.Contract"
    clr_name = item.fetch("args").fetch(0)
    pinned = BATCH_REFERENCE.fetch(clr_name)
    events = pinned.fetch("members").select { |member| member.fetch("kind") == "event" }
    [pinned.fetch("kind"), pinned["baseType"], pinned.fetch("members").length, events.length,
     events.map do |member|
       [member.fetch("name"), member.fetch("type"), member.fetch("add"), member.fetch("remove"),
        member.fetch("static")]
     end]
  when "EventProjection.SupportTypeContract"
    # The identities Foundation 20 established are passed as args rather than censused, so the row
    # pins what that milestone settled and survives the selection legitimately growing. What is
    # asserted of the whole selection is the *shape* -- every selected event is an
    # EventHandler`1 -- which is the rule the support type exists for.
    identities = item.fetch("args")
    declared = BATCH_SIGNATURES.values.flat_map do |type|
      type.fetch("members").select { |member| member.fetch("kind") == "event" }
          .map { |member| ["#{type.fetch("name")}::#{member.fetch("name")}", member.fetch("type")] }
    end.to_h
    [identities.map { |identity| declared.key?(identity) },
     identities.map { |identity| declared[identity] },
     declared.values.all? { |type| type.start_with?("System.EventHandler`1[") }]
  when "EventProjection.DeferredFamilyContract"
    %w[GameComponent DrawableGameComponent GameComponentCollection].map do |short|
      pinned = BATCH_REFERENCE.fetch("Microsoft.Xna.Framework.#{short}")
      events = pinned.fetch("members").select { |member| member.fetch("kind") == "event" }
      [short, events.map { |member| member.fetch("name") }, events.map { |member| member.fetch("type") }.uniq]
    end
  when "EventProjection.RubyMapping"
    clr_name = item.fetch("args").fetch(0)
    interface = batch_enum_type(clr_name)
    identities = BATCH_SIGNATURES.fetch(clr_name).fetch("members")
                                 .select { |member| member.fetch("kind") == "event" }
                                 .map { |member| member.fetch("name") }
    host = Class.new { include(interface) }
    [
      identities,
      interface.xna_event_identities.map(&:to_s),
      identities.map { |name| interface.public_method_defined?(name) },
      identities.map { |name| interface.method_defined?("#{name}=") },
      identities.map { |name| interface.method_defined?("add_#{name}") },
      identities.map { |name| interface.method_defined?("remove_#{name}") },
      identities.map { |name| error_name { host.allocate.public_send(name) } },
      identities.map do |name|
        begin
          host.allocate.public_send(name)
          "none"
        rescue Exception => error
          error.message
        end
      end
    ]
  when "EventRuntime.Surface"
    event = CNA::Runtime::Event
    [
      event.public_instance_methods(false).map(&:to_s).sort,
      event.protected_instance_methods(false).map(&:to_s).sort,
      %w[emit fire trigger call invoke notify broadcast publish raise_event dispatch subscribe
         unsubscribe clear << >>].map { |name| event.public_method_defined?(name) },
      event.private_method_defined?(:dispatch),
      event.superclass.name,
      Object.const_defined?(:System, false)
    ]
  when "EventRuntime.Subscription"
    event = CNA::Runtime::Event.new
    order = []
    first = ->(_sender, _args) { order << "first" }
    second = ->(_sender, _args) { order << "second" }
    event.add(first)
    event.add(second)
    event.add(first)
    event.__send__(:dispatch, :sender, CNA::Runtime::EventArgs::Empty)
    registered = order.dup
    order.clear
    removed = event.remove(first).equal?(first)
    event.__send__(:dispatch, :sender, CNA::Runtime::EventArgs::Empty)
    [registered, removed, order.dup, event.remove(:never_subscribed).nil?]
  when "EventRuntime.Dispatch"
    event = CNA::Runtime::Event.new
    seen = []
    late = ->(_sender, _args) { seen << "late" }
    event.add { |_sender, _args| seen << "first" }
    event.add { |_sender, _args| seen << "second"; event.add(late) }
    event.__send__(:dispatch, nil, CNA::Runtime::EventArgs::Empty)
    snapshot = seen.dup
    seen.clear
    event.__send__(:dispatch, nil, CNA::Runtime::EventArgs::Empty)
    reentrant = seen.dup

    failing = CNA::Runtime::Event.new
    log = []
    failing.add { |_sender, _args| log << "before" }
    failing.add { |_sender, _args| raise ArgumentError, "handler failed" }
    failing.add { |_sender, _args| log << "after" }
    [snapshot, reentrant, error_name { failing.__send__(:dispatch, nil, CNA::Runtime::EventArgs::Empty) }, log]
  when "EventRuntime.Validation"
    event = CNA::Runtime::Event.new
    [
      error_name { event.add },
      error_name { event.add(42) },
      error_name { event.add(->(only) { only }) },
      error_name { event.add(->(one, two, three) { [one, two, three] }) },
      error_name { event.add(->(_sender, _args) {}) { |_sender, _args| } },
      error_name { event.add(->(_sender, _args) {}) },
      error_name { event.add { |_sender, _args| } },
      error_name { event.add(->(*rest) { rest }) }
    ]
  when "EventRuntime.EventArgs"
    args = CNA::Runtime::EventArgs
    [args::Empty.instance_of?(args), args::Empty.frozen?, args::Empty.equal?(args::Empty),
     args.new.instance_of?(args), args.new.equal?(args::Empty),
     args.constants(false).map(&:to_s), args.public_instance_methods(false).map(&:to_s),
     args.superclass.name]
  when "EventRuntime.OwnerIsolation"
    owner = Class.new do
      extend CNA::Runtime::EventOwner
      xna_event :Changed
      def raise_changed(args) = self.Changed.__send__(:dispatch, self, args)
    end
    first = owner.new
    second = owner.new
    seen = []
    first.Changed.add { |sender, args| seen << [sender.equal?(first), args.equal?(CNA::Runtime::EventArgs::Empty)] }
    second.raise_changed(CNA::Runtime::EventArgs::Empty)
    isolated = seen.empty?
    first.raise_changed(CNA::Runtime::EventArgs::Empty)
    [first.Changed.equal?(second.Changed), first.Changed.equal?(first.Changed), isolated, seen,
     owner.xna_event_identities.map(&:to_s)]
  when "TouchPanelCapabilities.Contract"
    name = "Microsoft.Xna.Framework.Input.Touch.TouchPanelCapabilities"
    pinned = BATCH_REFERENCE.fetch(name)
    selected = BATCH_SIGNATURES.fetch(name)
    [pinned.fetch("kind"), pinned.fetch("baseType"), pinned.fetch("sealed"),
     pinned.fetch("members").length,
     pinned.fetch("members").map do |member|
       [member.fetch("name"), member.fetch("type"), member.fetch("get"), member.fetch("set")]
     end,
     selected.fetch("members").any? { |member| member.fetch("kind") == "constructor" }]
  when "TouchPanelCapabilities.DefaultValue"
    capabilities = TOUCH::TouchPanelCapabilities.new
    copy = capabilities.dup
    [
      capabilities.IsConnected,
      capabilities.MaximumTouchCount,
      capabilities.instance_of?(TOUCH::TouchPanelCapabilities),
      (TOUCH::TouchPanelCapabilities.public_instance_methods(false) - %i[dup clone]).map(&:to_s).sort,
      capabilities.respond_to?(:IsConnected=),
      capabilities.equal?(copy),
      copy.IsConnected == capabilities.IsConnected && copy.MaximumTouchCount == capabilities.MaximumTouchCount,
      TOUCH::TouchPanelCapabilities.respond_to?(:GetCapabilities)
    ]
  when "PureManagedEnum.Contract"
    clr_name = item.fetch("args").fetch(0)
    pinned = BATCH_REFERENCE.fetch(clr_name)
    selected = BATCH_SIGNATURES.fetch(clr_name)
    declared = pinned.fetch("members").reject { |member| member.fetch("name") == "value__" }
    [pinned.fetch("kind"), pinned.fetch("underlyingType"), pinned.fetch("flags"),
     declared.map { |member| [member.fetch("name"), Integer(member.fetch("value"))] },
     declared.length,
     pinned.fetch("members").length,
     pinned.fetch("members").any? { |member| member.fetch("name") == "value__" },
     selected.fetch("members").length,
     selected.fetch("members").any? { |member| member.fetch("name") == "value__" }]
  when "PureManagedEnum.RubyMapping"
    clr_name = item.fetch("args").fetch(0)
    type = batch_enum_type(clr_name)
    members = BATCH_SIGNATURES.fetch(clr_name).fetch("members")
    names = members.map { |member| member.fetch("name") }
    raws = members.map { |member| Integer(member.fetch("value")) }
    values = names.map { |name| type.const_get(name, false) }
    mask = raws.reduce(0) { |accumulator, raw| accumulator | raw }
    flags = type.instance_variable_get(:@enum_flags)
    foreign = [G::DepthFormat::Depth24, G::SurfaceFormat::Color,
               F::DisplayOrientation::Default, I::GamePadType::GamePad]
    undefined = if flags
                  [-1, mask + 1]
                else
                  ([-1, raws.max + 1] + (0..raws.max).to_a - raws).uniq
                end
    [
      type.constants(false).map(&:to_s).sort,
      values.map(&:to_i),
      values.all? { |value| value.instance_of?(type) },
      values.all?(&:frozen?),
      raws.map { |raw| type.coerce(raw).to_i },
      raws.map { |raw| type.coerce(raw).name },
      values.map { |value| type.coerce(value).equal?(value) },
      flags,
      type.instance_variable_get(:@enum_mask),
      values.map(&:to_s),
      values.map(&:inspect),
      [nil, true, false, 1.0, "1", :Literal, []].map { |bad| error_name { type.coerce(bad) } },
      foreign.map { |value| error_name { type.coerce(value) } },
      foreign.map { |value| values.first == value },
      foreign.map { |value| values.first <=> value },
      flags ? (values.first | values.last).to_i : error_name { values.first | values.last },
      flags ? (values.first & values.last).to_i : error_name { values.first & values.last },
      undefined.map { |raw| error_name { type.coerce(raw) } },
      flags ? (0..mask).select { |raw| (raw & ~mask).zero? }.map { |raw| type.coerce(raw).to_i } : [],
      type.public_instance_methods(false),
      %i[ToString HasFlag Parse FromInt32 GetValues to_native].map { |name| values.first.respond_to?(name) }
    ]
  when "PrimitiveType.Contract"
    members = PRIMITIVE_TYPE_SIGNATURE.fetch("members")
    [PRIMITIVE_TYPE_SIGNATURE.fetch("kind"), PRIMITIVE_TYPE_SIGNATURE.fetch("underlyingType"),
     PRIMITIVE_TYPE_SIGNATURE.fetch("flags"),
     members.map { |member| [member.fetch("name"), Integer(member.fetch("value"))] },
     members.length,
     members.any? { |member| Integer(member.fetch("value")).zero? },
     %w[PointList TriangleFan].map { |name| members.any? { |member| member.fetch("name") == name } }]
  when "PrimitiveType.RubyEnumMapping"
    topology = G::PrimitiveType
    values = [topology::TriangleList, topology::TriangleStrip, topology::LineList, topology::LineStrip]
    foreign = [G::DepthFormat::Depth24, G::SurfaceFormat::Color, G::SpriteSortMode::Deferred,
               G::GraphicsProfile::Reach, G::GraphicsDeviceStatus::Normal, G::ClearOptions::Target,
               F::DisplayOrientation::Default, G::VertexElementFormat::Vector2, I::GamePadType::GamePad]
    [
      values.all? { |value| value.instance_of?(topology) },
      values.all?(&:frozen?),
      values.map(&:to_i),
      (0..3).map { |raw| topology.coerce(raw).equal?(values[raw]) },
      values.all? { |value| topology.coerce(value).equal?(value) },
      [4, 5, -1, 12_345, 2_147_483_647].map { |raw| error_name { topology.coerce(raw) } },
      [nil, true, false, 1.0, "1", :LineList, Object.new].map { |value| error_name { topology.coerce(value) } },
      foreign.map { |value| error_name { topology.coerce(value) } },
      foreign.map { |value| topology::LineList == value },
      foreign.map { |value| topology::LineList <=> value },
      [error_name { topology::TriangleStrip | topology::LineList },
       error_name { topology::LineStrip & topology::LineList },
       error_name { topology::TriangleList | topology::LineStrip }],
      topology::TriangleStrip.to_i | topology::LineList.to_i,
      topology.instance_variable_get(:@enum_flags),
      topology.instance_variable_get(:@enum_mask),
      values.map(&:to_s),
      values.map(&:inspect),
      topology.constants(false).map(&:to_s).sort,
      %i[value__ PointList TriangleFan Default None].map { |name| topology.constants(false).include?(name) },
      %i[ToString HasFlag VertexCount PrimitiveCount NativeTopology GlEnum Parse FromInt32]
        .map { |name| topology::LineList.respond_to?(name) },
      %w[DrawPrimitives DrawIndexedPrimitives DrawInstancedPrimitives DrawUserPrimitives
         DrawUserIndexedPrimitives].map { |name| G::GraphicsDevice.public_method_defined?(name) },
      %i[VertexBuffer IndexBuffer VertexDeclaration RasterizerState Effect]
        .map { |name| G.const_defined?(name, false) },
      CNA::Native::Manifest::CONSTANTS.keys.any? { |name| name.include?("PRIMITIVE") || name.include?("TOPOLOGY") },
      CNA::Native::Manifest::FUNCTIONS.any? { |entry| entry.symbol.include?("primitive") || entry.symbol.include?("draw_") }
    ]
  when "GraphicsProfile.Contract"
    profile = G::GraphicsProfile
    values = [profile::Reach, profile::HiDef]
    [GRAPHICS_PROFILE_SIGNATURE.fetch("kind"),
     GRAPHICS_PROFILE_SIGNATURE.fetch("underlyingType"),
     profile.instance_variable_get(:@enum_flags), values.map(&:to_i)]
  when "GraphicsProfile.RubyEnumMapping"
    profile = G::GraphicsProfile
    values = [profile::Reach, profile::HiDef]
    foreign = [G::GraphicsDeviceStatus::Normal, F::DisplayOrientation::Default,
               G::SurfaceFormat::Color, G::SpriteSortMode::Deferred,
               F::PlayerIndex::One, I::GamePadDeadZone::None]
    [
      values.all? { |value| value.instance_of?(profile) },
      values.all?(&:frozen?),
      profile.coerce(0).equal?(profile::Reach),
      profile.coerce(1).equal?(profile::HiDef),
      profile.coerce(profile::Reach).equal?(profile::Reach),
      profile.coerce(profile::HiDef).equal?(profile::HiDef),
      [-1, 2].map { |value| error_name { profile.coerce(value) } },
      [nil, "1", 1.0, Object.new].map { |value| error_name { profile.coerce(value) } },
      foreign.map { |value| error_name { profile.coerce(value) } },
      error_name { profile::Reach | profile::HiDef },
      error_name { profile::HiDef & profile::Reach },
      foreign.map { |value| profile::Reach == value },
      foreign.map { |value| profile::Reach <=> value },
      values.map(&:to_s),
      profile::HiDef.inspect,
      profile.constants(false).map(&:to_s).sort,
      profile.constants(false).include?(:value__),
      profile::Reach.respond_to?(:ToString),
      profile::Reach.respond_to?(:HasFlag),
      profile.instance_variable_get(:@enum_mask)
    ]
  when "GraphicsDeviceStatus.Contract"
    status = G::GraphicsDeviceStatus
    values = [status::Normal, status::Lost, status::NotReset]
    [GRAPHICS_DEVICE_STATUS_SIGNATURE.fetch("kind"),
     GRAPHICS_DEVICE_STATUS_SIGNATURE.fetch("underlyingType"),
     status.instance_variable_get(:@enum_flags), values.map(&:to_i)]
  when "GraphicsDeviceStatus.RubyEnumMapping"
    status = G::GraphicsDeviceStatus
    values = [status::Normal, status::Lost, status::NotReset]
    foreign = [F::DisplayOrientation::Default, G::SpriteEffects::None, I::Buttons::DPadUp,
               G::SurfaceFormat::Color, F::PlayerIndex::One]
    [
      values.all? { |value| value.instance_of?(status) },
      values.all?(&:frozen?),
      status.coerce(0).equal?(status::Normal),
      status.coerce(1).equal?(status::Lost),
      status.coerce(2).equal?(status::NotReset),
      status.coerce(status::NotReset).equal?(status::NotReset),
      error_name { status.coerce(3) },
      foreign.map { |value| error_name { status.coerce(value) } },
      error_name { status::Normal | status::Lost },
      error_name { status::NotReset & status::Lost },
      foreign.map { |value| status::Normal == value },
      foreign.map { |value| status::Normal <=> value },
      values.map(&:to_s),
      status::Lost.inspect,
      status.constants(false).map(&:to_s).sort,
      status.constants(false).include?(:value__),
      status::Normal.respond_to?(:ToString),
      status.instance_variable_get(:@enum_mask)
    ]
  when "DisplayOrientation.Contract"
    values = [F::DisplayOrientation::Default, F::DisplayOrientation::LandscapeLeft,
              F::DisplayOrientation::LandscapeRight, F::DisplayOrientation::Portrait]
    [values.map(&:to_i), F::DisplayOrientation.instance_variable_get(:@enum_flags)]
  when "DisplayOrientation.RubyFlagsMapping"
    orientation = F::DisplayOrientation
    combinations = [
      orientation::LandscapeLeft | orientation::LandscapeRight,
      orientation::LandscapeLeft | orientation::Portrait,
      orientation::LandscapeRight | orientation::Portrait,
      orientation::LandscapeLeft | orientation::LandscapeRight | orientation::Portrait
    ]
    left_portrait = combinations[1]
    [
      orientation.coerce(0).equal?(orientation::Default),
      orientation.coerce(1).equal?(orientation::LandscapeLeft),
      orientation.coerce(2).equal?(orientation::LandscapeRight),
      orientation.coerce(4).equal?(orientation::Portrait),
      orientation.coerce(orientation::Portrait).equal?(orientation::Portrait),
      combinations.map(&:to_i),
      combinations.all? { |value| value.instance_of?(orientation) },
      combinations.all?(&:frozen?),
      (left_portrait & orientation::LandscapeLeft).equal?(orientation::LandscapeLeft),
      (left_portrait & orientation::LandscapeRight).equal?(orientation::Default),
      (combinations[3] & orientation::Portrait).equal?(orientation::Portrait),
      error_name { orientation.coerce(8) },
      error_name { orientation.coerce(9) },
      error_name { orientation.coerce(0x100) },
      error_name { orientation.coerce(nil) },
      error_name { orientation::LandscapeLeft | G::SpriteEffects::FlipHorizontally },
      error_name { orientation::LandscapeLeft | I::Buttons::DPadUp },
      error_name { orientation::LandscapeLeft | F::PlayerIndex::One },
      orientation::Portrait.respond_to?(:ToString),
      orientation::Portrait.respond_to?(:HasFlag),
      orientation.instance_variable_get(:@enum_mask)
    ]
  when "VertexElement.Enums"
    formats = %i[Single Vector2 Vector3 Vector4 Color Byte4 Short2 Short4 NormalizedShort2
                 NormalizedShort4 HalfVector2 HalfVector4].map { |name| G::VertexElementFormat.const_get(name) }
    usages = %i[Position Color TextureCoordinate Normal Binormal Tangent BlendIndices BlendWeight
                Depth Fog PointSize Sample TessellateFactor].map { |name| G::VertexElementUsage.const_get(name) }
    [formats.map(&:to_i), usages.map(&:to_i), formats.all? { |value| value.instance_of?(G::VertexElementFormat) && value.frozen? },
     usages.all? { |value| value.instance_of?(G::VertexElementUsage) && value.frozen? },
     G::VertexElementFormat.instance_variable_get(:@enum_flags),
     G::VertexElementUsage.instance_variable_get(:@enum_flags)]
  when "VertexElement.EnumNames"
    [G::VertexElementFormat.constants(false).sort_by { |name| G::VertexElementFormat.const_get(name).to_i }
       .map { |name| G::VertexElementFormat.const_get(name).to_s },
     G::VertexElementUsage.constants(false).sort_by { |name| G::VertexElementUsage.const_get(name).to_i }
       .map { |name| G::VertexElementUsage.const_get(name).to_s }]
  when "VertexElement.EnumValidation"
    [error_name { G::VertexElementFormat.coerce(12) }, error_name { G::VertexElementUsage.coerce(13) },
     error_name { G::VertexElementFormat.coerce(G::VertexElementUsage::Position) },
     error_name { G::VertexElementFormat::Single | G::VertexElementFormat::Vector2 },
     error_name { G::VertexElementUsage::Position | G::VertexElementUsage::Color },
     G::VertexElementFormat::Single.respond_to?(:SizeInBytes),
     G::VertexElementUsage::Position.respond_to?(:ComponentCount)]
  when "VertexElement.Default"
    value = G::VertexElement.new
    explicit = G::VertexElement.new(0, G::VertexElementFormat::Single, G::VertexElementUsage::Position, 0)
    [value.Offset, value.VertexElementFormat.to_i, value.VertexElementUsage.to_i, value.UsageIndex,
     value.GetHashCode, value.ToString, value == explicit]
  when "VertexElement.Constructor"
    value = G::VertexElement.new(12, G::VertexElementFormat::Vector3,
                                 G::VertexElementUsage::TextureCoordinate, 7)
    [value.Offset, value.VertexElementFormat.to_i, value.VertexElementUsage.to_i,
     value.UsageIndex, value.ToString]
  when "VertexElement.Setters"
    value = G::VertexElement.new
    value.Offset = -16
    value.VertexElementFormat = G::VertexElementFormat::HalfVector4
    value.VertexElementUsage = G::VertexElementUsage::Tangent
    value.UsageIndex = -3
    [value.Offset, value.VertexElementFormat.to_i, value.VertexElementUsage.to_i, value.UsageIndex]
  when "VertexElement.Int32Boundaries"
    [0, 1, -1, -2_147_483_648, 2_147_483_647].flat_map do |number|
      value = G::VertexElement.new(number, G::VertexElementFormat::Single,
                                   G::VertexElementUsage::Position, number)
      [value.Offset, value.UsageIndex]
    end
  when "VertexElement.Copy"
    value = G::VertexElement.new(12, G::VertexElementFormat::Vector3,
                                 G::VertexElementUsage::TextureCoordinate, 7)
    duplicate = value.dup
    clone = value.clone
    duplicate.Offset = -16
    duplicate.VertexElementFormat = G::VertexElementFormat::HalfVector4
    duplicate.VertexElementUsage = G::VertexElementUsage::Tangent
    duplicate.UsageIndex = -3
    clone.Offset = 1
    clone.VertexElementFormat = G::VertexElementFormat::Color
    clone.VertexElementUsage = G::VertexElementUsage::Normal
    clone.UsageIndex = 9
    [!duplicate.equal?(value), !clone.equal?(value), value.Offset, value.VertexElementFormat.to_i,
     value.VertexElementUsage.to_i, value.UsageIndex, duplicate.Offset,
     duplicate.VertexElementFormat.to_i, duplicate.VertexElementUsage.to_i, duplicate.UsageIndex,
     clone.Offset, clone.VertexElementFormat.to_i, clone.VertexElementUsage.to_i, clone.UsageIndex]
  when "VertexElement.Equality"
    value = G::VertexElement.new(12, G::VertexElementFormat::Vector3,
                                 G::VertexElementUsage::TextureCoordinate, 7)
    equal = value.dup
    different = G::VertexElement.new(13, G::VertexElementFormat::Vector3,
                                     G::VertexElementUsage::TextureCoordinate, 7)
    [value.Equals(equal), value == equal, value != equal, value.Equals(nil), value.Equals(Object.new),
     value == different, value != different]
  when "VertexElement.FieldDifferences"
    value = G::VertexElement.new(12, G::VertexElementFormat::Vector3,
                                 G::VertexElementUsage::TextureCoordinate, 7)
    [G::VertexElement.new(13, G::VertexElementFormat::Vector3, G::VertexElementUsage::TextureCoordinate, 7),
     G::VertexElement.new(12, G::VertexElementFormat::Vector4, G::VertexElementUsage::TextureCoordinate, 7),
     G::VertexElement.new(12, G::VertexElementFormat::Vector3, G::VertexElementUsage::Normal, 7),
     G::VertexElement.new(12, G::VertexElementFormat::Vector3, G::VertexElementUsage::TextureCoordinate, 8)]
      .map { |other| value != other }
  when "VertexElement.HashGoldens"
    [G::VertexElement.new,
     G::VertexElement.new(12, G::VertexElementFormat::Vector3, G::VertexElementUsage::TextureCoordinate, 7),
     G::VertexElement.new(-16, G::VertexElementFormat::HalfVector4, G::VertexElementUsage::Tangent, -3),
     G::VertexElement.new(-2_147_483_648, G::VertexElementFormat::HalfVector4,
                          G::VertexElementUsage::TessellateFactor, 2_147_483_647),
     G::VertexElement.new(1, G::VertexElementFormat::Vector3, G::VertexElementUsage::Normal, 0),
     G::VertexElement.new(2_147_483_647, G::VertexElementFormat::Single,
                          G::VertexElementUsage::Position, -2_147_483_648)].map(&:GetHashCode)
  when "VertexElement.StringGoldens"
    [G::VertexElement.new,
     G::VertexElement.new(12, G::VertexElementFormat::Vector3, G::VertexElementUsage::TextureCoordinate, 7),
     G::VertexElement.new(-16, G::VertexElementFormat::HalfVector4, G::VertexElementUsage::Tangent, -3),
     G::VertexElement.new(-2_147_483_648, G::VertexElementFormat::HalfVector4,
                          G::VertexElementUsage::TessellateFactor, 2_147_483_647)].map(&:ToString)
  when "VertexElement.ConstructorValidation"
    [error_name { G::VertexElement.new(0) },
     error_name { G::VertexElement.new(0.0, G::VertexElementFormat::Single, G::VertexElementUsage::Position, 0) },
     error_name { G::VertexElement.new(-2_147_483_649, G::VertexElementFormat::Single, G::VertexElementUsage::Position, 0) },
     error_name { G::VertexElement.new(0, G::VertexElementFormat::Single, G::VertexElementUsage::Position, 2_147_483_648) },
     error_name { G::VertexElement.new(0, G::VertexElementUsage::Position, G::VertexElementUsage::Position, 0) },
     error_name { G::VertexElement.new(0, G::VertexElementFormat::Single, G::VertexElementFormat::Single, 0) },
     error_name { G::VertexElement.new(0, 12, G::VertexElementUsage::Position, 0) },
     error_name { G::VertexElement.new(0, G::VertexElementFormat::Single, 13, 0) }]
  when "VertexElement.SetterValidationSurface"
    value = G::VertexElement.new
    [error_name { value.Offset = nil }, error_name { value.Offset = 2_147_483_648 },
     error_name { value.UsageIndex = 1.0 }, error_name { value.UsageIndex = -2_147_483_649 },
     error_name { value.VertexElementFormat = G::VertexElementUsage::Position },
     error_name { value.VertexElementFormat = -1 },
     error_name { value.VertexElementUsage = G::VertexElementFormat::Single },
     error_name { value.VertexElementUsage = 99 }, value.respond_to?(:Format), value.respond_to?(:Usage),
     value.respond_to?(:SizeInBytes), value.respond_to?(:VertexDeclaration)]
  when "ButtonState.Values"
    [I::ButtonState::Released.to_i, I::ButtonState::Pressed.to_i,
     I::ButtonState::Released.instance_of?(I::ButtonState), I::ButtonState::Pressed.frozen?]
  when "ButtonState.Validation"
    [error_name { I::ButtonState.coerce(2) }, error_name { I::ButtonState.coerce(true) },
     error_name { I::ButtonState::Released | I::ButtonState::Pressed }]
  when "MouseState.Properties"
    value = mouse_state(args)
    [value.X, value.Y, value.LeftButton.to_i, value.RightButton.to_i, value.MiddleButton.to_i,
     value.XButton1.to_i, value.XButton2.to_i, value.ScrollWheelValue]
  when "MouseState.Equals"
    left = mouse_state(args[0]); right = mouse_state(args[1])
    [left.Equals(right), left == right, left != right]
  when "MouseState.HashString"
    value = mouse_state(args)
    [value.GetHashCode, value.ToString]
  when "MouseState.Extremes"
    minimum = -2_147_483_648; maximum = 2_147_483_647
    low = mouse_state([minimum, maximum, minimum, 0, 0, 0, 0, 0])
    high = mouse_state([maximum, minimum, maximum, 1, 1, 1, 1, 1])
    [low.GetHashCode, low.ToString, high.GetHashCode, high.ToString]
  when "MouseState.ValueSemantics"
    value = mouse_state(args); copy = value.dup; equal_before = value.Equals(copy)
    copy.instance_variable_set(:@X, 44)
    [equal_before, !value.equal?(copy), value.X, copy.X, value.LeftButton.frozen?]
  when "GamePad.Enums"
    [[I::GamePadDeadZone::None, I::GamePadDeadZone::IndependentAxes, I::GamePadDeadZone::Circular].map(&:to_i),
     [I::GamePadType::Unknown, I::GamePadType::GamePad, I::GamePadType::Wheel,
      I::GamePadType::ArcadeStick, I::GamePadType::FlightStick, I::GamePadType::DancePad,
      I::GamePadType::Guitar, I::GamePadType::AlternateGuitar,
      I::GamePadType::DrumKit, I::GamePadType::BigButtonPad].map(&:to_i)]
  when "GamePad.EnumsValidation"
    [error_name { I::GamePadDeadZone.coerce(3) }, error_name { I::GamePadType.coerce(9) },
     error_name { I::GamePadDeadZone::None | I::GamePadDeadZone::Circular }]
  when "Buttons.Values"
    %i[DPadUp DPadDown DPadLeft DPadRight Start Back LeftStick RightStick LeftShoulder
       RightShoulder BigButton A B X Y RightThumbstickUp RightThumbstickDown
       RightThumbstickRight RightThumbstickLeft LeftThumbstickUp LeftThumbstickDown
       LeftThumbstickRight LeftThumbstickLeft RightTrigger LeftTrigger]
      .map { |name| I::Buttons.const_get(name).to_i }
  when "Buttons.Composition"
    combined = I::Buttons::A | I::Buttons::B | I::Buttons::LeftThumbstickRight
    [combined.to_i, (combined & I::Buttons::B).to_i, I::Buttons.coerce(0).to_i,
     I::Buttons.coerce(0x7fe0_fbff).to_i]
  when "Buttons.Validation"
    [error_name { I::Buttons.coerce(0x400) }, error_name { I::Buttons.coerce(0x8000_0000) },
     error_name { I::Buttons.coerce(true) }]
  when "Buttons.HighBits"
    [(I::Buttons::LeftThumbstickRight | I::Buttons::LeftThumbstickUp).to_i,
     (I::Buttons::RightThumbstickLeft | I::Buttons::LeftTrigger).to_i,
     (I::Buttons::LeftThumbstickRight & I::Buttons::LeftThumbstickRight).to_i]
  when "GamePadButtons.Properties"
    value = I::GamePadButtons.new(buttons(args[0]))
    %i[A B Back X Y Start LeftShoulder LeftStick RightShoulder RightStick BigButton]
      .map { |property| value.public_send(property).to_i }
  when "GamePadButtons.HashString"
    values = [0, I::Buttons::A.to_i, (I::Buttons::A | I::Buttons::B).to_i, 0x0000_fbf0]
    values.flat_map do |mask|
      value = I::GamePadButtons.new(buttons(mask)); [value.GetHashCode, value.ToString]
    end
  when "GamePadButtons.VirtualSurface"
    value = I::GamePadButtons.new(I::Buttons::LeftTrigger | I::Buttons::LeftThumbstickLeft)
    [value == I::GamePadButtons.new(buttons(0)), value.respond_to?(:LeftTrigger),
     value.respond_to?(:LeftThumbstickLeft), value.ToString]
  when "GamePadButtons.EqualityCopy"
    value = I::GamePadButtons.new(I::Buttons::A | I::Buttons::Back); copy = value.dup
    [value.Equals(copy), value == copy, value != copy, !value.equal?(copy), value.Equals(Object.new)]
  when "GamePadDPad.Properties"
    value = I::GamePadDPad.new(*args.map { |entry| button(entry) })
    [value.Up.to_i, value.Down.to_i, value.Right.to_i, value.Left.to_i]
  when "GamePadDPad.HashString"
    values = [[0, 0, 0, 0], [1, 0, 0, 0], [1, 0, 1, 0], [1, 1, 1, 1]]
    values.flat_map do |states|
      value = I::GamePadDPad.new(*states.map { |entry| button(entry) })
      [value.GetHashCode, value.ToString]
    end
  when "GamePadDPad.EqualityCopy"
    value = I::GamePadDPad.new(button(1), button(0), button(0), button(1)); copy = value.dup
    [value.Equals(copy), value == copy, value != copy, !value.equal?(copy), value.Equals(Object.new)]
  when "GamePadDPad.Validation"
    [error_name { I::GamePadDPad.new(true, button(0), button(0), button(0)) },
     error_name { I::GamePadDPad.new(button(0), button(0), button(0)) }]
  when "GamePadTriggers.Clamp"
    [[-1.0, 2.0], [0.0, 0.5], [1.0, 1.5]].flat_map do |pair|
      value = I::GamePadTriggers.new(*pair); hex_values([value.Left, value.Right])
    end
  when "GamePadTriggers.Special"
    value = I::GamePadTriggers.new(-0.0, Float::NAN)
    infinity = I::GamePadTriggers.new(-Float::INFINITY, Float::INFINITY)
    [hex32(value.Left), value.Right.nan?, hex32(infinity.Left), hex32(infinity.Right)]
  when "GamePadTriggers.HashString"
    value = I::GamePadTriggers.new(0.25, 0.75); zero = I::GamePadTriggers.new(0, 0)
    [value.GetHashCode, value.ToString, zero.GetHashCode, zero.ToString]
  when "GamePadTriggers.Equality"
    value = I::GamePadTriggers.new(0.25, 0.75); nan = I::GamePadTriggers.new(Float::NAN, 0)
    [value.Equals(value.dup), value == value.dup, value != I::GamePadTriggers.new(0.25, 0.5),
     nan.Equals(nan)]
  when "GamePadTriggers.Copy"
    value = I::GamePadTriggers.new(0.25, 0.75); copy = value.dup
    copy.instance_variable_set(:@Left, 1.0)
    [!value.equal?(copy), value.Left, copy.Left]
  when "GamePadThumbSticks.Clamp"
    value = I::GamePadThumbSticks.new(F::Vector2.new(2, -2), F::Vector2.new(0.25, -0.5))
    hex_values([value.Left.X, value.Left.Y, value.Right.X, value.Right.Y])
  when "GamePadThumbSticks.Special"
    value = I::GamePadThumbSticks.new(F::Vector2.new(Float::NAN, Float::INFINITY),
                                      F::Vector2.new(-Float::INFINITY, -0.0))
    hex_values([value.Left.X, value.Left.Y, value.Right.X, value.Right.Y])
  when "GamePadThumbSticks.HashString"
    value = I::GamePadThumbSticks.new(F::Vector2.new(0.25, -0.5), F::Vector2.new(0.75, -1))
    zero = I::GamePadThumbSticks.new(F::Vector2.Zero, F::Vector2.Zero)
    [value.GetHashCode, value.ToString, zero.GetHashCode]
  when "GamePadThumbSticks.Copy"
    value = I::GamePadThumbSticks.new(F::Vector2.new(0.25, 0.5), F::Vector2.Zero)
    left = value.Left; left.X = 1.0
    [!left.equal?(value.Left), left.X, value.Left.X, !value.dup.equal?(value)]
  when "GamePadThumbSticks.Equality"
    value = I::GamePadThumbSticks.new(F::Vector2.new(0.25, 0.5), F::Vector2.new(0.75, 1))
    [value.Equals(value.dup), value == value.dup,
     value != I::GamePadThumbSticks.new(F::Vector2.new(0.25, 0.5), F::Vector2.Zero)]
  when "GamePadState.ComponentConstructor"
    value = I::GamePadState.new(
      I::GamePadThumbSticks.new(F::Vector2.new(0.5, 0), F::Vector2.Zero),
      I::GamePadTriggers.new(0.25, 0), I::GamePadButtons.new(I::Buttons::A),
      I::GamePadDPad.new(button(1), button(0), button(0), button(0))
    )
    [value.IsConnected, value.PacketNumber, value.Buttons.A.to_i, value.DPad.Up.to_i,
     value.ThumbSticks.Left.X, value.Triggers.Left]
  when "GamePadState.ArrayConstructor"
    zero = F::Vector2.Zero
    empty = I::GamePadState.new(zero, zero, 0, 0, []); null = I::GamePadState.new(zero, zero, 0, 0, nil)
    repeated = I::GamePadState.new(zero, zero, 0, 0, [I::Buttons::A, I::Buttons::A])
    combined = I::GamePadState.new(zero, zero, 0, 0, [I::Buttons::A | I::Buttons::B, I::Buttons::DPadRight])
    virtual = I::GamePadState.new(zero, zero, 0, 0, [I::Buttons::LeftTrigger])
    [empty == null, repeated.IsButtonDown(I::Buttons::A),
     combined.IsButtonDown(I::Buttons::A | I::Buttons::B | I::Buttons::DPadRight),
     virtual.IsButtonDown(I::Buttons::LeftTrigger)]
  when "GamePadState.Thresholds"
    numeric = CNA::Runtime::Numeric
    at = I::GamePadState.new(F::Vector2.new(numeric.div32(7_849, 32_767), 0), F::Vector2.Zero,
                             numeric.div32(30, 255), 0, [])
    over = I::GamePadState.new(F::Vector2.new(numeric.div32(7_850, 32_767), 0), F::Vector2.Zero,
                               numeric.div32(31, 255), 0, [])
    [at.IsButtonDown(I::Buttons::LeftThumbstickRight), at.IsButtonDown(I::Buttons::LeftTrigger),
     over.IsButtonDown(I::Buttons::LeftThumbstickRight), over.IsButtonDown(I::Buttons::LeftTrigger)]
  when "GamePadState.CombinedFlags"
    value = I::GamePadState.new(F::Vector2.new(0.5, 0), F::Vector2.Zero, 0.5, 0,
                                [I::Buttons::A, I::Buttons::DPadUp])
    [value.IsButtonDown(I::Buttons::A | I::Buttons::DPadUp | I::Buttons::LeftTrigger |
                        I::Buttons::LeftThumbstickRight),
     value.IsButtonDown(I::Buttons::A | I::Buttons::B),
     value.IsButtonUp(I::Buttons::A | I::Buttons::B),
     value.IsButtonDown(buttons(0)), value.IsButtonUp(buttons(0))]
  when "GamePadState.HashString"
    value = I::GamePadState.new(
      I::GamePadThumbSticks.new(F::Vector2.Zero, F::Vector2.Zero),
      I::GamePadTriggers.new(0, 0), I::GamePadButtons.new(I::Buttons::A),
      I::GamePadDPad.new(button(1), button(0), button(0), button(0))
    )
    [value.GetHashCode, value.ToString]
  when "GamePadState.EqualityCopy"
    args = [F::Vector2.new(0.5, 0), F::Vector2.Zero, 0.25, 0.75, [I::Buttons::A]]
    value = I::GamePadState.new(*args); copy = value.dup
    [value.Equals(copy), value == copy, value != copy, !value.equal?(copy), value.Equals(Object.new)]
  when "GamePadState.NestedCopies"
    value = I::GamePadState.new(F::Vector2.new(0.5, 0), F::Vector2.Zero, 0.25, 0.75, [I::Buttons::A])
    first = [value.ThumbSticks, value.Triggers, value.Buttons, value.DPad]
    second = [value.ThumbSticks, value.Triggers, value.Buttons, value.DPad]
    first[0].instance_variable_get(:@Left).X = -1.0
    [first.zip(second).all? { |left, right| !left.equal?(right) }, value.ThumbSticks.Left.X,
     first[0].Left.X]
  when "PackedVector.PackedValue"
    type_name, values = args
    packed_type(type_name).new(*values).PackedValue
  when "PackedVector.HalfBits"
    input_bits = Integer(args[0], 16)
    value = PV::HalfSingle.new(CNA::Runtime::Numeric.f32_from_bits(input_bits))
    [value.PackedValue, hex32(value.ToSingle), value.ToString]
  when "PackedVector.Interface"
    type_name, initial, lanes = args
    value = packed_type(type_name).new(*initial)
    value.__send__(:PackFromVector4, vector4(lanes))
    expanded = value.__send__(:ToVector4)
    [value.PackedValue, *hex_values(vector4_result(expanded))]
  when "PackedVector.ValueSemantics"
    type_name, initial, packed = args
    value = packed_type(type_name).new(*initial)
    value.PackedValue = packed
    copy = value.dup
    [value.GetHashCode, value.ToString, value.Equals(copy), value == copy, value != copy, !value.equal?(copy)]
  when "MathHelper.Clamp" then F::MathHelper.Clamp(*args)
  when "MathHelper.Lerp" then F::MathHelper.Lerp(*args)
  when "MathHelper.Barycentric" then F::MathHelper.Barycentric(*args)
  when "MathHelper.CatmullRom" then F::MathHelper.CatmullRom(*args)
  when "MathHelper.Hermite" then F::MathHelper.Hermite(*args)
  when "MathHelper.SmoothStep" then F::MathHelper.SmoothStep(*args)
  when "MathHelper.WrapAngle" then F::MathHelper.WrapAngle(*args)
  when "MathHelper.ToDegrees" then F::MathHelper.ToDegrees(*args)
  when "Vector2.Add" then vector_result(F::Vector2.Add(vector(args[0]), vector(args[1])))
  when "Vector2.Dot" then F::Vector2.Dot(vector(args[0]), vector(args[1]))
  when "Vector2.Normalize" then vector_result(F::Vector2.Normalize(vector(args[0])))
  when "Vector2.Reflect" then vector_result(F::Vector2.Reflect(vector(args[0]), vector(args[1])))
  when "Vector2.Barycentric" then vector_result(F::Vector2.Barycentric(vector(args[0]), vector(args[1]), vector(args[2]), args[3], args[4]))
  when "Vector2.Transform" then vector_result(F::Vector2.Transform(vector(args[0]), F::Matrix.CreateTranslation(*args[1])))
  when "Vector2.ZeroFresh"
    left = F::Vector2.Zero; right = F::Vector2.Zero; !left.equal?(right)
  when "Vector3.Cross" then vector3_result(F::Vector3.Cross(vector3(args[0]), vector3(args[1])))
  when "Vector3.Distance" then F::Vector3.Distance(vector3(args[0]), vector3(args[1]))
  when "Vector3.Reflect" then vector3_result(F::Vector3.Reflect(vector3(args[0]), vector3(args[1])))
  when "Vector3.TransformNormal" then vector3_result(F::Vector3.TransformNormal(vector3(args[0]), F::Matrix.CreateScale(*args[1])))
  when "Vector3.SmoothStep" then vector3_result(F::Vector3.SmoothStep(vector3(args[0]), vector3(args[1]), args[2]))
  when "Vector4.Dot" then F::Vector4.Dot(vector4(args[0]), vector4(args[1]))
  when "Vector4.Hermite" then vector4_result(F::Vector4.Hermite(vector4(args[0]), vector4(args[1]), vector4(args[2]), vector4(args[3]), args[4]))
  when "Vector4.Transform" then vector4_result(F::Vector4.Transform(vector4(args[0]), F::Matrix.CreateTranslation(*args[1])))
  when "Quaternion.AxisAngleZero" then quaternion_result(F::Quaternion.CreateFromAxisAngle(F::Vector3.UnitY, 0))
  when "Quaternion.YawPitchRoll" then quaternion_result(F::Quaternion.CreateFromYawPitchRoll(*args))
  when "Quaternion.Concatenate"
    quaternion_result(F::Quaternion.Concatenate(F::Quaternion.CreateFromAxisAngle(F::Vector3.UnitX, args[0]), F::Quaternion.CreateFromAxisAngle(F::Vector3.UnitY, args[1])))
  when "Quaternion.SlerpIdentity" then quaternion_result(F::Quaternion.Slerp(F::Quaternion.Identity, F::Quaternion.CreateFromAxisAngle(F::Vector3.UnitY, args[0]), args[1]))
  when "Quaternion.FromMatrix" then quaternion_result(F::Quaternion.CreateFromRotationMatrix(F::Matrix.CreateRotationY(args[0])))
  when "Matrix.Translation"
    value = F::Matrix.CreateTranslation(*args); [value.M41, value.M42, value.M43, value.M44]
  when "Matrix.MultiplyTranslations"
    value = F::Matrix.CreateTranslation(1, 2, 3) * F::Matrix.CreateTranslation(4, 5, 6); [value.M41, value.M42, value.M43, value.M44]
  when "Matrix.InverseProduct"
    value = F::Matrix.CreateScale(*args[0]) * F::Matrix.CreateTranslation(*args[1]); matrix_result(value * F::Matrix.Invert(value))
  when "Matrix.SingularInverseNaN" then matrix_result(F::Matrix.Invert(F::Matrix.new)).all?(&:nan?)
  when "Matrix.RotationY"
    value = F::Matrix.CreateRotationY(args[0]); [value.M11, value.M13, value.M31, value.M33]
  when "Matrix.PerspectiveInfinity"
    value = F::Matrix.CreatePerspective(args[0], args[1], args[2], Float::INFINITY); [value.M33.nan?, value.M43.nan?]
  when "Matrix.Decompose"
    success, scale, rotation, translation = (F::Matrix.CreateScale(*args[0]) * F::Matrix.CreateTranslation(*args[1])).Decompose
    [success, *vector3_result(scale), *quaternion_result(rotation), *vector3_result(translation)]
  when "Matrix.Billboard"
    value = F::Matrix.CreateBillboard(vector3(args[0]), vector3(args[1]), vector3(args[2]), nil)
    [value.M11, value.M22, value.M33, *vector3_result(value.Translation)]
  when "Matrix.Orthographic"
    value = F::Matrix.CreateOrthographic(*args); [value.M11, value.M22, value.M33, value.M43, value.M44]
  when "Color.Bytes" then color_result(color(args))
  when "Color.Packed" then color(args).PackedValue
  when "Color.Lerp" then color_result(F::Color.Lerp(color(args[0]), color(args[1]), args[2]))
  when "Color.Multiply" then color_result(F::Color.Multiply(color(args[0]), args[1]))
  when "Color.FloatConstructors"
    tie_zero = CNA::Runtime::Numeric.div32(0.5, 255.0)
    tie_two = CNA::Runtime::Numeric.div32(2.5, 255.0)
    [F::Color.new(0.0, 1.0, 0.5).PackedValue,
     F::Color.new(0.5, Float::NAN, Float::INFINITY, -Float::INFINITY).PackedValue,
     F::Color.new(tie_zero, tie_two, tie_zero, tie_two).PackedValue]
  when "Color.VectorConstructors"
    [F::Color.new(vector3(args[0])).PackedValue, F::Color.new(vector4(args[1])).PackedValue]
  when "Color.FromNonPremultipliedVector"
    [F::Color.FromNonPremultiplied(vector4(args[0])).PackedValue,
     F::Color.FromNonPremultiplied(F::Vector4.new(Float::NAN, Float::INFINITY, -Float::INFINITY, Float::INFINITY)).PackedValue]
  when "Color.FromNonPremultipliedInt"
    args.map { |alpha| F::Color.FromNonPremultiplied(255, 128, 64, alpha).PackedValue }
  when "Color.ToVectorBits"
    value3 = F::Color.new(*args[0]).ToVector3
    value4 = F::Color.new(*args[1]).ToVector4
    hex_values([*vector3_result(value3), *vector4_result(value4)])
  when "Color.Palette"
    contract = JSON.parse(File.read(File.expand_path("api_compat/signatures.json", __dir__)))
    type = contract.fetch("types").find { |candidate| candidate["name"] == "Microsoft.Xna.Framework.Color" }
    names = type.fetch("members").filter_map do |member|
      member["name"] if member["kind"] == "property" && member["static"]
    end
    text = names.map { |name| "#{name}=#{F::Color.public_send(name).PackedValue}\n" }.join
    [names.length, Digest::SHA256.hexdigest(text), names.all? { |name| !F::Color.public_send(name).equal?(F::Color.public_send(name)) }]
  when "Color.LerpEdges"
    low = F::Color.new(10, 200, 50, 255); high = F::Color.new(110, 0, 250, 0)
    [-1.0, 0.0, 0.5, 1.0, 2.0, Float::NAN, Float::INFINITY, -Float::INFINITY].map do |amount|
      F::Color.Lerp(low, high, amount).PackedValue
    end
  when "Color.MultiplyEdges"
    value = F::Color.new(1, 100, 200, 255)
    [0.0, 1.0, 0.5, -1.0, 2.0, Float::NAN, Float::INFINITY, -Float::INFINITY].map do |scale|
      F::Color.Multiply(value, scale).PackedValue
    end
  when "Color.ValueSemantics"
    value = F::Color.new(1, 2, 3, 255); copy = value.dup; copy.R = 9
    [F::Color.Transparent.PackedValue, value.GetHashCode, value.ToString, value == F::Color.new(1, 2, 3, 255), value.R, copy.R]
  when "Rectangle.Contains" then F::Rectangle.new(*args[0, 4]).Contains(args[4], args[5])
  when "Rectangle.Intersect" then rectangle_result(F::Rectangle.Intersect(rectangle(args[0]), rectangle(args[1])))
  when "Rectangle.Union" then rectangle_result(F::Rectangle.Union(rectangle(args[0]), rectangle(args[1])))
  when "Rectangle.Inflate"
    value = rectangle(args[0]); value.Inflate(*args[1]); rectangle_result(value)
  when "Rectangle.Offset"
    value = rectangle(args[0]); value.Offset(*args[1]); rectangle_result(value)
  when "Rectangle.Boundaries"
    value = rectangle(args)
    [value.Contains(value.Left, value.Top), value.Contains(value.Right, value.Top),
     value.Contains(value.Left, value.Bottom), value.Contains(value.Right - 1, value.Bottom - 1)]
  when "Rectangle.Degenerate"
    value = rectangle(args)
    [value.Intersects(F::Rectangle.new(5, 5, 0, 0)),
     value.Intersects(F::Rectangle.new(5, 5, -1, -1)),
     value.Intersects(F::Rectangle.Empty), value.Contains(F::Rectangle.new(5, 5, -1, -1))]
  when "Rectangle.RefOutProjection"
    value = rectangle(args[0]); other = rectangle(args[1])
    [value.Contains(F::Point.new(other.X, other.Y)), value.Contains(other), value.Intersects(other),
     *rectangle_result(F::Rectangle.Intersect(value, other)), *rectangle_result(F::Rectangle.Union(value, other))]
  when "Rectangle.Overflow"
    maximum = 2_147_483_647; minimum = -2_147_483_648
    value = F::Rectangle.new(maximum, minimum, 1, -1)
    before = [value.Right, value.Bottom, value.Center.X, value.Center.Y]
    value.Offset(1, -1)
    inflated = F::Rectangle.new(minimum, maximum, maximum, minimum); inflated.Inflate(1, -1)
    [*before, *rectangle_result(value), *rectangle_result(inflated)]
  when "Rectangle.IntersectionEdges"
    base = rectangle(args)
    [*rectangle_result(F::Rectangle.Intersect(base, F::Rectangle.new(10, 0, 5, 5))),
     *rectangle_result(F::Rectangle.Intersect(base, F::Rectangle.new(9, 9, 5, 5))),
     *rectangle_result(F::Rectangle.Intersect(base, F::Rectangle.new(2, 2, 3, 3)))]
  when "Rectangle.UnionOverflow"
    maximum = 2_147_483_647; minimum = -2_147_483_648
    [*rectangle_result(F::Rectangle.Union(F::Rectangle.new(maximum, 0, 2, 1), F::Rectangle.new(minimum, 0, 1, 1))),
     *rectangle_result(F::Rectangle.Union(F::Rectangle.new(minimum, minimum, 0, 0), F::Rectangle.new(maximum, maximum, 0, 0)))]
  when "Rectangle.ValueSemantics"
    value = rectangle(args); copy = value.dup; copy.X = 9
    [value.GetHashCode, value.ToString, value == rectangle(args), value.X, copy.X,
     !value.Location.equal?(value.Location), !value.Center.equal?(value.Center), !F::Rectangle.Empty.equal?(F::Rectangle.Empty)]
  when "CurveKey.Constructors"
    short = F::CurveKey.new(1.0 / 3.0, 2.0 / 3.0)
    four = F::CurveKey.new(1, 2, 3, 4)
    five = F::CurveKey.new(1, 2, 3, 4, F::CurveContinuity::Step)
    [hex32(short.Position), hex32(short.Value), hex32(short.TangentIn), hex32(short.TangentOut),
     short.Continuity.to_i, four.Continuity.to_i, five.Continuity.to_i, short.respond_to?(:Position=)]
  when "CurveKey.Clone"
    value = F::CurveKey.new(1, 2, 3, 4, F::CurveContinuity::Step); clone = value.Clone
    equal_before = value.Equals(clone); clone.Value = 20
    [!clone.equal?(value), equal_before, value.Value, clone.Value]
  when "CurveKey.Equality"
    value = F::CurveKey.new(1, 2, 3, 4, F::CurveContinuity::Step)
    nan = F::CurveKey.new(Float::NAN, 1)
    positive_zero = F::CurveKey.new(0.0, -0.0); negative_zero = F::CurveKey.new(-0.0, 0.0)
    [value.GetHashCode, value == value.Clone, nan == nan, positive_zero == negative_zero,
     positive_zero.GetHashCode, negative_zero.GetHashCode]
  when "CurveKey.Compare"
    low = F::CurveKey.new(-1, 0); equal = F::CurveKey.new(-1, 99); high = F::CurveKey.new(1, 0)
    nan_a = F::CurveKey.new(Float::NAN, 0); nan_b = F::CurveKey.new(Float::NAN, 0)
    [low.CompareTo(high), low.CompareTo(equal), high.CompareTo(low), nan_a.CompareTo(low),
     low.CompareTo(nan_a), nan_a.CompareTo(nan_b), F::CurveKey.new(-Float::INFINITY, 0).CompareTo(low),
     F::CurveKey.new(Float::INFINITY, 0).CompareTo(high), F::CurveKey.new(0.0, 0).CompareTo(F::CurveKey.new(-0.0, 1))]
  when "CurveCollection.Ordering"
    keys = F::CurveKeyCollection.new; first = F::CurveKey.new(1, 10); second = F::CurveKey.new(1, 20)
    keys.Add(F::CurveKey.new(2, 30)); keys.Add(first); keys.Add(F::CurveKey.new(0, 0)); keys.Add(second)
    [[0, 1, 2, 3].map { |index| keys[index].Position }, [0, 1, 2, 3].map { |index| keys[index].Value },
     keys[1].equal?(first), keys[2].equal?(second)]
  when "CurveCollection.Replacement"
    keys = F::CurveKeyCollection.new; keys.Add(F::CurveKey.new(0, 1)); keys.Add(F::CurveKey.new(5.0e-8, 2))
    replacement = F::CurveKey.new(1.0e-7, 3); keys[0] = replacement
    same = F::CurveKey.new(1.0e-7, 4); keys[1] = same
    [hex32(keys[0].Value), hex32(keys[1].Value), keys[1].equal?(same)]
  when "CurveCollection.CopyClone"
    keys = F::CurveKeyCollection.new; first = F::CurveKey.new(0, 1); second = F::CurveKey.new(1, 2)
    keys.Add(first); keys.Add(second); destination = Array.new(4); keys.CopyTo(destination, 1); clone = keys.Clone
    clone[0].Value = 42; clone.Add(F::CurveKey.new(2, 3))
    [destination[1].equal?(first), destination[2].equal?(second), !clone.equal?(keys),
     clone[0].equal?(keys[0]), keys[0].Value, keys.Count, clone.Count]
  when "CurveCollection.Enumeration"
    keys = F::CurveKeyCollection.new; first = F::CurveKey.new(0, 0); second = F::CurveKey.new(1, 1)
    keys.Add(first); keys.Add(second); left = keys.GetEnumerator; right = keys.GetEnumerator
    fresh = !left.equal?(right) && left.next.equal?(first) && right.next.equal?(first)
    invalid = keys.GetEnumerator; invalid.next; keys.Add(F::CurveKey.new(2, 2)); failure = error_name { invalid.next }
    safe = keys.GetEnumerator; keys.CopyTo(Array.new(keys.Count), 0)
    [fresh, failure, safe.next.equal?(first), [second, keys[2]] == [safe.next, safe.next]]
  when "CurveCollection.Validation"
    keys = F::CurveKeyCollection.new; keys.Add(F::CurveKey.new(0, 0))
    [error_name { keys[-1] }, error_name { keys.RemoveAt(keys.Count) },
     error_name { keys.Add(nil) }, error_name { keys.CopyTo([], -1) }, error_name { keys.CopyTo([], 0) }]
  when "CurveEvaluate.Defaults"
    value = F::Curve.new; same_keys = value.Keys.equal?(value.Keys); empty = hex32(value.Evaluate(5)); value.Keys.Add(F::CurveKey.new(5, 7))
    singleton = hex32(value.Evaluate(Float::NAN)); one_constant = value.IsConstant; value.Keys.Add(F::CurveKey.new(6, 7))
    [value.PreLoop.to_i, value.PostLoop.to_i, same_keys, empty, one_constant, singleton, value.IsConstant]
  when "CurveEvaluate.Hermite"
    ordinary = F::Curve.new; ordinary.Keys.Add(F::CurveKey.new(0, 0)); ordinary.Keys.Add(F::CurveKey.new(1, 10))
    asymmetric = F::Curve.new; asymmetric.Keys.Add(F::CurveKey.new(0, 0, 99, 4)); asymmetric.Keys.Add(F::CurveKey.new(2, 10, -2, 77))
    [hex32(ordinary.Evaluate(0.25)), hex32(asymmetric.Evaluate(1))]
  when "CurveEvaluate.Step"
    value = F::Curve.new; value.Keys.Add(F::CurveKey.new(0, 2, 0, 0, F::CurveContinuity::Step)); value.Keys.Add(F::CurveKey.new(1, 9))
    [hex32(value.Evaluate(0.999)), hex32(value.Evaluate(1))]
  when "CurveEvaluate.Duplicates"
    value = F::Curve.new; value.Keys.Add(F::CurveKey.new(1, 10)); value.Keys.Add(F::CurveKey.new(1, 20))
    value.PreLoop = F::CurveLoopType::Cycle; value.PostLoop = F::CurveLoopType::Oscillate
    nan_step = F::Curve.new; nan_step.Keys.Add(F::CurveKey.new(0, 10, 0, 0, F::CurveContinuity::Step)); nan_step.Keys.Add(F::CurveKey.new(1, 20, 0, 0, F::CurveContinuity::Step))
    [hex32(value.Evaluate(0)), hex32(value.Evaluate(1)), hex32(value.Evaluate(2)), hex32(nan_step.Evaluate(Float::NAN))]
  when "CurveTangents.Modes"
    value = F::Curve.new; [[0, 0], [1, 10], [3, 30]].each { |key| value.Keys.Add(F::CurveKey.new(*key)) }
    value.ComputeTangents(F::CurveTangent::Smooth)
    hex_values([value.Keys[0].TangentIn, value.Keys[1].TangentIn, value.Keys[1].TangentOut, value.Keys[2].TangentOut])
  when "CurveTangents.Mixed"
    value = F::Curve.new; [[0, 0], [2, 10], [5, 40]].each { |key| value.Keys.Add(F::CurveKey.new(*key)) }
    value.ComputeTangent(1, F::CurveTangent::Flat, F::CurveTangent::Linear); first = [value.Keys[1].TangentIn, value.Keys[1].TangentOut]
    value.ComputeTangent(1, F::CurveTangent::Linear, F::CurveTangent::Smooth)
    hex_values([*first, value.Keys[1].TangentIn, value.Keys[1].TangentOut])
  when "CurveTangents.Epsilon"
    value = F::Curve.new; [[0, 0], [1, 5.0e-9], [2, 1.0e-8]].each { |key| value.Keys.Add(F::CurveKey.new(*key)) }
    value.ComputeTangent(1, F::CurveTangent::Smooth); hex_values([value.Keys[1].TangentIn, value.Keys[1].TangentOut])
  when "CurveTangents.Duplicate"
    value = F::Curve.new; [[1, 0], [1, 1], [1, 2]].each { |key| value.Keys.Add(F::CurveKey.new(*key)) }
    value.ComputeTangent(1, F::CurveTangent::Smooth)
    singleton = F::Curve.new; singleton.Keys.Add(F::CurveKey.new(1, 9, 2, 3)); singleton.ComputeTangents(F::CurveTangent::Smooth)
    [value.Keys[1].TangentIn.nan?, value.Keys[1].TangentOut.nan?, singleton.Keys[0].TangentIn, singleton.Keys[0].TangentOut]
  when "CurveLoops.All"
    results = []
    [F::CurveLoopType::Constant, F::CurveLoopType::Cycle, F::CurveLoopType::CycleOffset,
     F::CurveLoopType::Oscillate, F::CurveLoopType::Linear].each do |mode|
      value = F::Curve.new; value.Keys.Add(F::CurveKey.new(5, 0)); value.Keys.Add(F::CurveKey.new(7, 10))
      value.Keys[0].TangentIn = 2; value.Keys[1].TangentOut = 3; value.PreLoop = mode; value.PostLoop = mode
      results.concat([hex32(value.Evaluate(4)), hex32(value.Evaluate(8))])
    end
    results
  when "CurveLoops.NegativeExact"
    [F::CurveLoopType::Cycle, F::CurveLoopType::CycleOffset, F::CurveLoopType::Oscillate].map do |mode|
      value = F::Curve.new; value.Keys.Add(F::CurveKey.new(5, 0)); value.Keys.Add(F::CurveKey.new(7, 10)); value.PreLoop = mode
      hex32(value.Evaluate(3))
    end
  when "CurveLoops.NormalizedBoundaries"
    value = F::Curve.new; value.Keys.Add(F::CurveKey.new(5, 10, 0, 0, F::CurveContinuity::Step)); value.Keys.Add(F::CurveKey.new(7, 20, 0, 0, F::CurveContinuity::Step))
    value.PreLoop = F::CurveLoopType::Cycle; value.PostLoop = F::CurveLoopType::Cycle
    [4.8, 3.0, 2.8, 1.0, 7.0, 7.2].map { |position| value.Evaluate(position) }
  when "CurveLoops.Formulas"
    signed = F::Curve.new; signed.Keys.Add(F::CurveKey.new(0, -0.0)); signed.Keys.Add(F::CurveKey.new(1, Float::NAN))
    descending = F::Curve.new; descending.Keys.Add(F::CurveKey.new(0, 10)); descending.Keys.Add(F::CurveKey.new(1, 0)); descending.PostLoop = F::CurveLoopType::CycleOffset
    linear = F::Curve.new; linear.Keys.Add(F::CurveKey.new(5, 0, 2, 0)); linear.Keys.Add(F::CurveKey.new(7, 10, 0, 3)); linear.PreLoop = F::CurveLoopType::Linear; linear.PostLoop = F::CurveLoopType::Linear
    [hex32(signed.Evaluate(-1)), hex32(signed.Evaluate(2)), hex32(descending.Evaluate(1.5)),
     hex32(linear.Evaluate(4)), hex32(linear.Evaluate(9))]
  when "Point.Equal" then F::Point.new(args[0], args[1]) == F::Point.new(args[2], args[3])
  when "Point.ZeroFresh" then !F::Point.Zero.equal?(F::Point.Zero)
  when "Plane.Normalize"
    value = F::Plane.new(vector3(args[0]), args[1]); result = F::Plane.Normalize(value); [*vector3_result(result.Normal), result.D]
  when "Plane.DotCoordinate" then F::Plane.new(vector3(args[0]), args[1]).DotCoordinate(vector3(args[2]))
  when "Plane.Box" then F::Plane.new(vector3(args[0]), args[1]).Intersects(box(args[2])).to_i
  when "Plane.Sphere" then F::Plane.new(vector3(args[0]), args[1]).Intersects(sphere(args[2])).to_i
  when "Ray.Box" then F::Ray.new(vector3(args[0]), vector3(args[1])).Intersects(box(args[2]))
  when "Ray.Sphere" then F::Ray.new(vector3(args[0]), vector3(args[1])).Intersects(sphere(args[2]))
  when "Ray.Plane" then F::Ray.new(vector3(args[0]), vector3(args[1])).Intersects(F::Plane.new(vector3(args[2]), args[3]))
  when "BoundingBox.ContainsPoint" then box(args[0]).Contains(vector3(args[1])).to_i
  when "BoundingBox.ContainsSphere" then box(args[0]).Contains(sphere(args[1])).to_i
  when "BoundingBox.Merge"
    value = F::BoundingBox.CreateMerged(box(args[0]), box(args[1])); [*vector3_result(value.Min), *vector3_result(value.Max)]
  when "BoundingSphere.ContainsPoint" then sphere(args[0]).Contains(vector3(args[1])).to_i
  when "BoundingSphere.Merge"
    value = F::BoundingSphere.CreateMerged(sphere(args[0]), sphere(args[1])); [*vector3_result(value.Center), value.Radius]
  when "BoundingSphere.Transform"
    value = sphere(args[0]).Transform(F::Matrix.CreateScale(*args[1]) * F::Matrix.CreateTranslation(*args[2])); [*vector3_result(value.Center), value.Radius]
  when "Frustum.ContainsPoint", "Frustum.ContainsBox", "Frustum.IntersectsSphere", "Frustum.Ray", "Frustum.Corners"
    frustum = F::BoundingFrustum.new(F::Matrix.CreatePerspectiveFieldOfView(F::MathHelper::PiOver2, 1, 1, 10))
    case item.fetch("operation")
    when "Frustum.ContainsPoint" then frustum.Contains(vector3(args[0])).to_i
    when "Frustum.ContainsBox" then frustum.Contains(box(args[0])).to_i
    when "Frustum.IntersectsSphere" then frustum.Intersects(sphere(args[0]))
    when "Frustum.Ray" then frustum.Intersects(F::Ray.new(vector3(args[0]), vector3(args[1])))
    when "Frustum.Corners" then [frustum.GetCorners.length, frustum.GetCorners[0].Z, frustum.GetCorners[4].Z]
    end
  when "Golden.Vector2NormalizeZero" then hex_values(vector_result(F::Vector2.Normalize(F::Vector2.Zero)))
  when "Golden.Vector3NormalizeZero" then hex_values(vector3_result(F::Vector3.Normalize(F::Vector3.Zero)))
  when "Golden.Vector4NormalizeZero" then hex_values(vector4_result(F::Vector4.Normalize(F::Vector4.Zero)))
  when "Golden.VectorDivide" then hex_values([(F::Vector2.new(3) / 7).X, (F::Vector3.new(7) / 3).X, (F::Vector4.new(12_345.67) / 3).X, (F::Matrix.Identity / 3).M11])
  when "Golden.QuaternionZero" then hex_values([*quaternion_result(F::Quaternion.Normalize(F::Quaternion.new)), *quaternion_result(F::Quaternion.Inverse(F::Quaternion.new))])
  when "Golden.QuaternionProducts"
    yaw = F::Quaternion.CreateFromAxisAngle(F::Vector3.Up, 0.7); pitch = F::Quaternion.CreateFromAxisAngle(F::Vector3.Right, -0.4)
    grouped = F::Quaternion.new(45_889.05859375, -42_412.4453125, 96_034.96875, -76_386.84375) * F::Quaternion.new(-16_375.435546875, 51_428.1875, -69_603.09375, -2_207.3798828125)
    hex_values([*quaternion_result(yaw * pitch), *quaternion_result(grouped), *quaternion_result(F::Quaternion.Concatenate(yaw, pitch)), *vector3_result(F::Vector3.Transform(F::Vector3.new(1.25, -2.5, 3.75), yaw * pitch))])
  when "Golden.MatrixTransforms"
    matrix = F::Matrix.CreateScale(2, 3, 4) * F::Matrix.CreateRotationY(0.25) * F::Matrix.CreateTranslation(5, 6, 7)
    hex_values([*vector_result(F::Vector2.Transform(F::Vector2.new(1.5, -2), matrix)), *vector3_result(F::Vector3.Transform(F::Vector3.new(1.5, -2, 0.25), matrix)), *vector4_result(F::Vector4.Transform(F::Vector4.new(1.5, -2, 0.25, 1), matrix))])
  when "Golden.PlaneTransform"
    value = F::Plane.Transform(F::Plane.new(F::Vector3.Up, -2), F::Matrix.CreateTranslation(0, 5, 0)); hex_values([*vector3_result(value.Normal), value.D])
  when "Golden.NaNEquality"
    vector_value = F::Vector2.new(Float::NAN, 0); matrix = F::Matrix.Identity; matrix.M11 = Float::NAN
    [vector_value.Equals(vector_value), vector_value == vector_value, matrix.Equals(matrix), matrix == matrix]
  when "Golden.HashCodes" then [F::Vector3.new(1, 2, 3).GetHashCode, F::Matrix.Identity.GetHashCode, F::Point.new(1, 2).GetHashCode, F::Rectangle.new(1, 2, 3, 4).GetHashCode]
  when "Golden.MathEdges"
    [hex32(F::MathHelper.Clamp(0, 2, 1)), hex32(F::MathHelper.WrapAngle(123_456.789)), hex32(F::MathHelper.CatmullRom(-10, -10, -10, -7, 0.3)), hex32(F::MathHelper.Hermite(-10, -10, -10, -10, 1.1)), F::MathHelper.Hermite(1, Float::INFINITY, 2, 0, 0).nan?]
  when "Golden.VectorEdges"
    nan = float_from_bits(0xFFC00000); minimum = F::Vector3.Min(F::Vector3.new(nan, 1, nan), F::Vector3.new(7, nan, nan)); clamped = F::Vector3.Clamp(F::Vector3.Zero, F::Vector3.new(2), F::Vector3.new(1))
    hex_values([*vector3_result(minimum), *vector3_result(clamped)])
  when "Golden.QuaternionEdges"
    yaw = F::Quaternion.CreateFromAxisAngle(F::Vector3.Up, 0.7); pitch = F::Quaternion.CreateFromAxisAngle(F::Vector3.Right, -0.4)
    hex_values([*quaternion_result(F::Quaternion.Slerp(yaw, pitch, 0.37)), *quaternion_result(F::Quaternion.CreateFromAxisAngle(F::Vector3.Up, 123_456.789)), *quaternion_result(F::Quaternion.CreateFromRotationMatrix(F::Matrix.CreateRotationY(0.7)))])
  when "Golden.MatrixEdges"
    large = F::Matrix.CreateRotationY(123_456.789); perspective = F::Matrix.CreatePerspective(4, 3, 0.1, Float::INFINITY)
    mirrored = F::Matrix.CreateScale(-2, 3, 4) * F::Matrix.CreateRotationY(0.25) * F::Matrix.CreateTranslation(5, 6, 7); ok, scale, rotation, translation = mirrored.Decompose
    [hex32(large.M11), hex32(large.M31), hex32(perspective.M33), hex32(perspective.M43), ok, *hex_values([*vector3_result(scale), *quaternion_result(rotation), *vector3_result(translation)]), *hex_values([(-F::Vector4.Zero).X, (-F::Quaternion.new).X, (-F::Matrix.new).M11])]
  when "Golden.MatrixDegenerate"
    billboard = F::Matrix.CreateConstrainedBillboard(F::Vector3.new(0, 10, 0), F::Vector3.Zero, F::Vector3.new(0, 2, 0), nil, nil)
    shadow = F::Matrix.CreateShadow(F::Vector3.Forward, F::Plane.new(F::Vector3.Zero, 0)); plane = F::Plane.new(F::Vector3.new(2, 0, 0), 4); reflection = F::Matrix.CreateReflection(plane); look = F::Matrix.CreateLookAt(F::Vector3.Zero, F::Vector3.Zero, F::Vector3.Up)
    [*hex_values([billboard.M11, billboard.M22, billboard.M33]), shadow.M11.nan?, shadow.M44.nan?, *hex_values([plane.Normal.X, plane.D, reflection.M11, reflection.M41]), *hex_values(matrix_result(look))]
  when "Golden.PlaneEdges"
    degenerate = F::Plane.new(F::Vector3.Zero, F::Vector3.Zero, F::Vector3.Zero); near = F::Plane.Normalize(F::Plane.new(F::Vector3.new(0.6, 0.79999995, 0), 2)); coplanar = F::Plane.new(F::Vector3.Zero, 0).Intersects(F::BoundingBox.new(F::Vector3.new(-1), F::Vector3.new(1)))
    [*hex_values([*vector3_result(degenerate.Normal), degenerate.D, *vector3_result(near.Normal), near.D]), coplanar.to_i]
  when "Golden.GeometryEdges"
    volume = F::BoundingBox.new(F::Vector3.new(-1), F::Vector3.new(1)); nan_box = F::BoundingBox.new(F::Vector3.new(Float::NAN, -1, -1), F::Vector3.new(Float::NAN, 1, 1)); unit = F::BoundingSphere.new(F::Vector3.Zero, 1)
    [volume.Contains(F::Vector3.new(Float::NAN, 0, 0)).to_i, volume.Intersects(nan_box), unit.Contains(F::Vector3.UnitX).to_i, unit.Intersects(F::BoundingSphere.new(F::Vector3.new(2, 0, 0), 1)), F::Ray.new(F::Vector3.new(2, 0, 0), F::Vector3.new(-5e-7, 0, 0)).Intersects(volume), F::Ray.new(F::Vector3.Zero, F::Vector3.new(5e-6, 1, 0)).Intersects(F::Plane.new(F::Vector3.UnitX, -1))]
  when "Golden.FrustumPlanesCorners"
    projection = F::Matrix.CreatePerspectiveFieldOfView(F::MathHelper::PiOver4, 4.0 / 3.0, 1, 10); frustum = F::BoundingFrustum.new(F::Matrix.CreateLookAt(F::Vector3.new(0, 0, 5), F::Vector3.Zero, F::Vector3.Up) * projection); corners = frustum.GetCorners
    hex_values([*vector3_result(frustum.Near.Normal), frustum.Near.D, *vector3_result(frustum.Top.Normal), frustum.Top.D, *vector3_result(corners[0]), *vector3_result(corners[6])])
  when "Golden.FrustumRelations"
    projection = F::Matrix.CreatePerspectiveFieldOfView(F::MathHelper::PiOver4, 4.0 / 3.0, 1, 10); frustum = F::BoundingFrustum.new(F::Matrix.CreateLookAt(F::Vector3.new(0, 0, 5), F::Vector3.Zero, F::Vector3.Up) * projection); distant = F::BoundingFrustum.new(F::Matrix.CreateLookAt(F::Vector3.new(100, 0, 5), F::Vector3.new(100, 0, 0), F::Vector3.Up) * projection)
    [frustum.Contains(F::Vector3.Zero).to_i, frustum.Contains(F::Vector3.new(0, 0, 6)).to_i, frustum.Contains(F::BoundingBox.new(F::Vector3.new(-0.5), F::Vector3.new(0.5))).to_i, frustum.Contains(F::BoundingSphere.new(F::Vector3.Zero, 0.5)).to_i, frustum.Intersects(F::BoundingBox.new(F::Vector3.new(-0.5), F::Vector3.new(0.5))), frustum.Intersects(F::BoundingBox.new(F::Vector3.new(100), F::Vector3.new(101))), frustum.Intersects(F::BoundingSphere.new(F::Vector3.Zero, 0.5)), frustum.Intersects(F::BoundingSphere.new(F::Vector3.new(100), 0.5)), frustum.Intersects(distant), hex32(frustum.Intersects(F::Ray.new(F::Vector3.new(0, 0, 20), F::Vector3.Forward)))]
  when "GameComponent.Contract"
    type = BATCH_REFERENCE.fetch("Microsoft.Xna.Framework.GameComponent")
    members = type.fetch("members")
    [type.fetch("kind"), type.fetch("sealed"), type.fetch("baseType"),
     type.fetch("directInterfaces").sort, members.length,
     members.select { |member| member.fetch("kind") == "event" }.map { |member| member.fetch("name") }.sort,
     members.select { |member| member.fetch("kind") == "property" }.map { |member| member.fetch("name") }.sort,
     members.count { |member| member.fetch("name") == "Dispose" }]
  when "GameComponent.ConstructorDefaults"
    game = F::Game.new
    begin
      component = F::GameComponent.new(game)
      orphan = F::GameComponent.new(nil)
      [component.Enabled, component.UpdateOrder, component.Game.equal?(game),
       orphan.Enabled, orphan.UpdateOrder, error_name { orphan.Dispose }]
    ensure
      game.Dispose
    end
  when "GameComponent.PropertyNotifications"
    game = F::Game.new
    begin
      component = F::GameComponent.new(game)
      raised = 0
      values = []
      component.EnabledChanged.add { |sender, args| raised += 1; values << [component.Enabled, sender.equal?(component), args.equal?(CNA::Runtime::EventArgs::Empty)] }
      component.UpdateOrderChanged.add { |sender, args| raised += 1; values << [component.UpdateOrder, sender.equal?(component), args.equal?(CNA::Runtime::EventArgs::Empty)] }
      component.Enabled = true
      component.UpdateOrder = 0
      suppressed = raised
      component.Enabled = false
      component.UpdateOrder = 7
      after = raised
      component.Enabled = false
      component.UpdateOrder = 7
      # A same-value write raises nothing; a real write raises once and the handler sees the new
      # value, the component as sender and EventArgs.Empty as args.
      [suppressed, after, raised, values[0][0], values[1][0],
       values.all? { |entry| entry[1] }, values.all? { |entry| entry[2] },
       component.Enabled == false]
    ensure
      game.Dispose
    end
  when "GameComponent.HooksIgnoreSender"
    game = F::Game.new
    begin
      component = F::GameComponent.new(game)
      other = F::GameComponent.new(game)
      senders = []
      component.EnabledChanged.add { |sender, _args| senders << sender }
      component.UpdateOrderChanged.add { |sender, _args| senders << sender }
      component.__send__(:OnEnabledChanged, other, CNA::Runtime::EventArgs::Empty)
      component.__send__(:OnUpdateOrderChanged, nil, CNA::Runtime::EventArgs::Empty)
      [senders[0].equal?(component), senders[1].equal?(component),
       senders[0].equal?(other), senders.include?(nil)]
    ensure
      game.Dispose
    end
  when "GameComponent.DisposeOrder"
    game = F::Game.new
    begin
      component = F::GameComponent.new(game)
      game.Components.Add(component)
      counts = []
      raised = 0
      component.Disposed.add { |_sender, _args| raised += 1; counts << game.Components.Count }
      component.Dispose
      first = raised
      component.Dispose
      second = raised
      component.Dispose
      # The removal happens before the notification, and no disposed flag stops the repeats.
      [counts.first, first, second, raised, game.Components.Count, counts.uniq.length, counts.last]
    ensure
      game.Dispose
    end
  when "GameComponent.DisposeFalseAndFinalize"
    game = F::Game.new
    begin
      component = F::GameComponent.new(game)
      game.Components.Add(component)
      raised = 0
      component.Disposed.add { |_sender, _args| raised += 1 }
      component.Dispose(false)
      after_false = [game.Components.Count, raised]
      component.__send__(:Finalize)
      after_finalize = [game.Components.Count, raised]
      [*after_false, *after_finalize, error_name { component.__send__(:Finalize) }]
    ensure
      game.Dispose
    end
  when "GameComponent.GameDisposesComponents"
    game = F::Game.new
    disposed = []
    components = Array.new(3) do
      component = F::GameComponent.new(game)
      component.Disposed.add { |sender, _args| disposed << sender }
      game.Components.Add(component)
      component
    end
    before = game.Components.Count
    game.Dispose
    [before, disposed.length, game.Components.Count, disposed == components]
  when "GameComponent.RubyProjection"
    klass = F::GameComponent
    [klass.ancestors.include?(F::IGameComponent),
     klass.ancestors.include?(F::IUpdateable),
     klass.ancestors.include?(F::IDrawable),
     klass.instance_method(:Dispose).arity,
     CNA::Runtime.const_defined?(:IDisposable, false),
     Object.const_defined?(:IDisposable, false),
     klass.public_method_defined?(:Finalize),
     klass.superclass.name]
  when "GameComponents.PropertyContract"
    game = BATCH_REFERENCE.fetch("Microsoft.Xna.Framework.Game")
    %w[Components Services].flat_map do |name|
      member = game.fetch("members").find { |entry| entry.fetch("name") == name }
      [member.fetch("type"), member.fetch("get"), member.fetch("set")]
    end
  when "GameComponents.StableIdentity"
    game = F::Game.new
    other = F::Game.new
    begin
      [game.Components.equal?(game.Components),
       game.Services.equal?(game.Services),
       game.Components.equal?(other.Components),
       game.Services.equal?(other.Services),
       game.Components.Count,
       game.instance_variable_get(:@host).nil?]
    ensure
      game.Dispose
      other.Dispose
    end
  when "GameComponents.ConstructionOrder"
    order = []
    services = F::GameServiceContainer
    collection = F::GameComponentCollection
    services.define_singleton_method(:new) { |*| order << "services"; super() }
    collection.define_singleton_method(:new) { |*| order << "components"; super() }
    game = F::Game.new
    begin
      [order[0], order[1], game.Components.Count,
       game.instance_variable_get(:@not_yet_initialized).length,
       game.Services.instance_variable_get(:@services).empty?]
    ensure
      services.singleton_class.__send__(:remove_method, :new)
      collection.singleton_class.__send__(:remove_method, :new)
      game.Dispose
    end
  when "GameComponents.OrderedInsertion"
    game = F::Game.new
    begin
      %w[first second third].each { |label| game.Components.Add(CorpusUpdateable.new(label, [], order: 5)) }
      game.Components.Add(CorpusUpdateable.new("high", [], order: 9))
      game.Components.Add(CorpusUpdateable.new("low", [], order: 1))
      stable = game.instance_variable_get(:@updateable_components).map(&:label)

      mixed = F::Game.new
      a = CorpusDrawable.new("a", [], order: 9, draw_order: 1)
      b = CorpusDrawable.new("b", [], order: 1, draw_order: 9)
      mixed.Components.Add(a)
      mixed.Components.Add(b)
      by_update = mixed.instance_variable_get(:@updateable_components).map(&:label)

      reorder = F::Game.new
      components = %w[a b c].each_with_index.map { |label, index| CorpusUpdateable.new(label, [], order: index + 1) }
      components.each { |component| reorder.Components.Add(component) }
      components[0].UpdateOrder = 10
      components[2].UpdateOrder = 0
      reordered = reorder.instance_variable_get(:@updateable_components).map(&:label)
      mixed.Dispose
      reorder.Dispose
      [stable, by_update, reordered]
    ensure
      game.Dispose
    end
  when "GameComponents.InitialisationQueue"
    log = []
    game = F::Game.new
    begin
      early = CorpusUpdateable.new("early", log)
      game.Components.Add(early)
      queued = game.instance_variable_get(:@not_yet_initialized).length
      before = corpus_labels(log, "initialize").length

      chained = F::Game.new
      chain_log = []
      late = CorpusUpdateable.new("late", chain_log)
      first = CorpusUpdateable.new("first", chain_log)
      first.define_singleton_method(:Initialize) do
        chain_log << ["initialize", "first"]
        chained.Components.Add(late)
      end
      chained.Components.Add(first)
      chained.__send__(:Initialize)
      drained = corpus_labels(chain_log, "initialize")
      remaining = chained.instance_variable_get(:@not_yet_initialized).length
      chained.Dispose

      game.__send__(:Initialize)
      [queued, before, drained, remaining, corpus_labels(log, "initialize")]
    ensure
      game.Dispose
    end
  when "GameComponents.UpdatePass"
    log = []
    game = F::Game.new
    begin
      game.Components.Add(CorpusUpdateable.new("a", log, order: 2))
      game.Components.Add(CorpusUpdateable.new("b", log, order: 1))
      game.__send__(:Update, F::GameTime.new)
      ordered = corpus_labels(log, "update")

      mutating = F::Game.new
      mutate_log = []
      late = CorpusUpdateable.new("late", mutate_log, order: 9)
      first = CorpusUpdateable.new("first", mutate_log, order: 1)
      first.define_singleton_method(:Update) do |_time|
        mutate_log << ["update", "first"]
        mutating.Components.Add(late) unless mutating.Components.Contains(late)
      end
      mutating.Components.Add(first)
      mutating.__send__(:Update, F::GameTime.new)
      first_pass = corpus_labels(mutate_log, "update")
      mutate_log.clear
      mutating.__send__(:Update, F::GameTime.new)
      second_pass = corpus_labels(mutate_log, "update")
      mutating.Dispose

      disabled = F::Game.new
      disabled_log = []
      component = CorpusUpdateable.new("a", disabled_log, enabled: false)
      disabled.Components.Add(component)
      disabled.__send__(:Update, F::GameTime.new)
      component.instance_variable_set(:@Enabled, true)
      disabled.__send__(:Update, F::GameTime.new)
      after_enable = corpus_labels(disabled_log, "update")
      disabled.Dispose

      [ordered, first_pass, second_pass, after_enable]
    ensure
      game.Dispose
    end
  when "GameComponents.DrawPass"
    log = []
    game = F::Game.new
    begin
      game.Components.Add(CorpusDrawable.new("a", log, draw_order: 2))
      game.Components.Add(CorpusDrawable.new("b", log, draw_order: 1))
      game.__send__(:Draw, F::GameTime.new)
      ordered = corpus_labels(log, "draw")

      hidden = F::Game.new
      hidden_log = []
      later = CorpusDrawable.new("later", hidden_log, draw_order: 2)
      first = CorpusDrawable.new("first", hidden_log, draw_order: 1)
      first.define_singleton_method(:Draw) do |_time|
        hidden_log << ["draw", "first"]
        later.Visible = false
      end
      hidden.Components.Add(first)
      hidden.Components.Add(later)
      hidden.__send__(:Draw, F::GameTime.new)
      visible_at_call_time = corpus_labels(hidden_log, "draw")
      no_device = hidden.GraphicsDevice.nil?
      hidden.Dispose

      [ordered, visible_at_call_time, no_device]
    ensure
      game.Dispose
    end
  when "GameComponents.RubySuperSemantics"
    suppressing = Class.new(F::Game) { def Update(game_time) = nil }
    calling = Class.new(F::Game) { def Update(game_time) = super }
    twice = Class.new(F::Game) do
      def Update(game_time)
        super
        super
      end
    end
    results = [suppressing, calling, twice].map do |klass|
      game = klass.new
      log = []
      game.Components.Add(CorpusUpdateable.new("a", log))
      game.__send__(:Update, F::GameTime.new)
      game.Dispose
      corpus_labels(log, "update")
    end
    results + [F::Game.method_defined?(:GameBaseUpdate),
               F::Game.respond_to?(:GameBaseUpdate),
               F::Game.protected_method_defined?(:Update)]
  when "GameComponents.NativeCallbackOrder"
    order = []
    klass = Class.new(F::Game) do
      define_method(:initialize) { super(); @frames = 0 }
      define_method(:Initialize) { order << "Initialize"; super() }
      define_method(:LoadContent) { order << "LoadContent"; super() }
      define_method(:BeginRun) { order << "BeginRun"; super() }
      define_method(:BeginDraw) { order << "BeginDraw"; super() }
      define_method(:Draw) { |time| order << "Draw"; super(time) }
      define_method(:EndDraw) { order << "EndDraw"; super() }
      define_method(:EndRun) { order << "EndRun"; super() }
      define_method(:Update) do |time|
        order << "Update"
        super(time)
        @frames += 1
        self.Exit if @frames >= 2
      end
    end
    game = klass.new
    before = game.instance_variable_get(:@in_run)
    flags = {}
    game.define_singleton_method(:record_flag) { |name| flags[name] = instance_variable_get(:@in_run) }
    game.Run
    after = game.instance_variable_get(:@in_run)
    game.Dispose
    # The flag is false through Initialize and LoadContent, true from BeginRun, and cleared once the
    # run is over.
    [order, before, after,
     order.index("Initialize") < order.index("LoadContent"),
     order.include?("UnloadContent")]
  when "DisposableCollapse.InterfaceContract"
    implementors = BATCH_REFERENCE.values.select do |type|
      type.fetch("directInterfaces", []).include?("System.IDisposable")
    end
    public_dispose = implementors.select do |type|
      type.fetch("members").any? do |member|
        member.fetch("name") == "Dispose" && member.fetch("parameters", []).empty? &&
          member["access"] == "public"
      end
    end
    explicit = implementors - public_dispose
    [implementors.length, public_dispose.length, explicit.length,
     explicit.map { |type| type.fetch("name") }.first,
     # System.IDisposable is a BCL type, so the XNA profile does not declare it.
     BATCH_REFERENCE.key?("System.IDisposable")]
  when "DisposableCollapse.Register"
    identity = item.fetch("args").fetch(0)
    register = CNA::Runtime::BclProjection
    short = identity.split(".").last.to_sym
    [register.structural_collapse?(identity),
     register::TYPES.key?(identity),
     register::EXCEPTION_BASES.key?(identity),
     register::THROWN_EXCEPTIONS.key?(identity),
     register.identities.include?(identity),
     Object.const_defined?(short, false),
     CNA::Runtime.const_defined?(short, false),
     F.const_defined?(short, false),
     Object.const_defined?(:System, false)]
  when "DisposableCollapse.NoInventedConventions"
    disposing = BATCH_SIGNATURES.values.select do |type|
      type.fetch("members").any? { |member| member.fetch("name") == "Dispose" }
    end
    # A name counts as invented only when the type's own reference contract does not declare it.
    # GameComponent really declares a protected Finalize, and GraphicsResource and GraphicsDevice
    # really declare IsDisposed; exempting them by rule keeps this row measuring the collapse rather
    # than a list of names.
    candidates = %i[Close close IsDisposed Finalize finalize dispose! release Release using owned?]
    leaks = disposing.sum do |type|
      klass = type.fetch("rubyName").split("::").reduce(Object) { |scope, part| scope.const_get(part, false) }
      declared = BATCH_REFERENCE.fetch(type.fetch("name")).fetch("members")
                                .map { |member| member.fetch("name").to_sym }
      (candidates - declared).count do |name|
        klass.public_method_defined?(name) || klass.protected_method_defined?(name)
      end
    end
    [leaks, disposing.count { |type| type.fetch("rubyName").include?("Disposable") },
     CNA::Runtime::BclProjection::TYPES.keys.count { |key| key.include?("IDisposable") },
     CNA::Runtime.const_defined?(:Disposable, false)]
  when "DisposableCollapse.FrontierEffect"
    frontier = JSON.parse(File.read(File.expand_path("../docs/generated/public-signature-dependency-report.json", __dir__)))
    by_name = frontier.fetch("dependencyCompleteCandidates").to_h { |entry| [entry.fetch("name"), entry] }
    instance = by_name.fetch("Microsoft.Xna.Framework.Audio.SoundEffectInstance")
    cue = by_name.fetch("Microsoft.Xna.Framework.Audio.Cue")
    content = by_name.fetch("Microsoft.Xna.Framework.Content.ContentManager")
    # Both audio types lose the BCL blocker and keep NATIVE_RUNTIME, so neither is consumable;
    # ContentManager named more than this one identity and keeps BCL_PROJECTION.
    [instance.fetch("blockers"), cue.fetch("blockers"),
     instance.fetch("unmappedBclTypes").empty? && cue.fetch("unmappedBclTypes").empty?,
     content.fetch("blockers").include?("BCL_PROJECTION"),
     frontier.fetch("consumableCandidates").length,
     frontier.fetch("mappedBclTypes").include?("System.IDisposable")]
  when "GameComponentCollection.Contract"
    type = BATCH_REFERENCE.fetch("Microsoft.Xna.Framework.GameComponentCollection")
    methods = type.fetch("members").select { |member| member.fetch("kind") == "method" }
                  .sort_by { |member| member.fetch("name") }
    [type.fetch("kind"), type.fetch("sealed"), type.fetch("baseType"),
     type.fetch("members").count { |member| member.fetch("kind") == "constructor" },
     methods.map { |member| member.fetch("name") },
     type.fetch("members").select { |member| member.fetch("kind") == "event" }
         .map { |member| member.fetch("name") }.sort,
     methods.map { |member| member.fetch("access") }]
  when "GameComponentCollection.InsertOrder"
    collection = F::GameComponentCollection.new
    counts = []
    collection.ComponentAdded.add { |_sender, _args| counts << collection.Count }
    first = corpus_component("a")
    collection.Add(first)
    refusal = error_name { collection.Add(first) }
    after_refusal = collection.Count
    removed_seen = 0
    collection.ComponentRemoved.add { |_sender, _args| removed_seen += 1 }
    collection.Add(corpus_component("b"))
    # count seen by the first handler, count seen after the duplicate refusal, the refusal itself,
    # the collection size the refusal left behind, how many removals were announced, the count the
    # second notification saw, and the final size.
    [counts.first, counts.length, refusal, after_refusal, removed_seen, counts.last, collection.Count]
  when "GameComponentCollection.RemoveOrder"
    collection = F::GameComponentCollection.new
    component = corpus_component("a")
    collection.Add(component)
    seen = []
    collection.ComponentRemoved.add { |sender, args| seen << [collection.Count, sender.equal?(collection), args.GameComponent.equal?(component)] }
    removed = collection.Remove(component)
    absent = error_name { collection.Remove(corpus_component("b")) }
    [seen.length, seen.first[0] + 1, seen.first[1] && seen.first[2], absent,
     collection.Count, collection.Remove(corpus_component("c")), seen.length - 1]
  when "GameComponentCollection.ClearOrder"
    collection = F::GameComponentCollection.new
    %w[a b c].each { |label| collection.Add(corpus_component(label)) }
    counts = []
    labels = []
    collection.ComponentRemoved.add do |_sender, args|
      counts << collection.Count
      labels << args.GameComponent.label
    end
    collection.Clear
    # Every announcement sees the full collection: no mutation happens until they are all done.
    [counts[0], counts[1], counts[2], counts.length, collection.Count, *labels]
  when "GameComponentCollection.ClearReReadsCount"
    collection = F::GameComponentCollection.new
    collection.Add(corpus_component("a"))
    late = corpus_component("late")
    labels = []
    collection.ComponentRemoved.add do |_sender, args|
      labels << args.GameComponent.label
      collection.Add(late) if args.GameComponent.label == "a"
    end
    collection.Clear
    [labels.length, labels[0], labels[1], collection.Count]
  when "GameComponentCollection.NullComponent"
    collection = F::GameComponentCollection.new
    announced = 0
    collection.ComponentAdded.add { |_sender, _args| announced += 1 }
    collection.Add(nil)
    inserted = collection.Count
    duplicate = error_name { collection.Add(nil) }
    after = collection.Count
    removals = []
    collection.ComponentRemoved.add { |_sender, args| removals << args.GameComponent.nil? }
    collection.Clear
    # Inserted silently, a second null is a duplicate, and ClearItems -- alone among the hooks --
    # has no null check, so it announces the null element.
    [inserted, announced, duplicate, after, collection.Count, removals.length, removals.first]
  when "GameComponentCollection.SetItemRefusal"
    collection = F::GameComponentCollection.new
    collection.Add(corpus_component("a"))
    [error_name { collection[0] = corpus_component("b") },
     error_name { collection[1] = corpus_component("b") },
     error_name { collection[-1] = corpus_component("b") },
     error_name { collection[0] = nil },
     collection.Count]
  when "GameComponentCollection.InheritedSurface"
    collection = F::GameComponentCollection.new
    first = corpus_component("a")
    second = corpus_component("b")
    collection.Add(first)
    collection.Insert(1, second)
    [collection.Count, collection.IndexOf(second), collection.IndexOf(corpus_component("c")),
     collection.Contains(first), collection.Contains(corpus_component("c")),
     error_name { collection[2] }, error_name { collection.RemoveAt(2) },
     error_name { collection.Insert(3, corpus_component("d")) }]
  when "GameComponentCollection.RubyBase"
    klass = F::GameComponentCollection
    [klass.superclass.name, klass.clr_element_types,
     klass.ancestors.include?(::Array), klass.ancestors.include?(CNA::Runtime::ReadOnlyCollection),
     klass.xna_event_identities.map(&:to_s)]
  when "GameComponentCollection.RubyEvents"
    collection = F::GameComponentCollection.new
    other = F::GameComponentCollection.new
    args = nil
    collection.ComponentAdded.add { |_sender, value| args = value }
    collection.Add(corpus_component("a"))
    [collection.ComponentAdded.class.name,
     collection.ComponentAdded.equal?(collection.ComponentAdded),
     collection.ComponentAdded.equal?(collection.ComponentRemoved),
     collection.ComponentAdded.equal?(other.ComponentAdded),
     args.class.name,
     F::GameComponentCollection.public_method_defined?(:add_ComponentAdded)]
  when "Float32.NegativeZero"
    value = CNA::Runtime::Numeric.f32(-0.0)
    value.zero? && (1.0 / value).negative?
  else raise "unsupported corpus operation #{item["operation"]}"
  end
end

corpus_path = File.expand_path("../behavior/xna40-foundation-values.json", __dir__)
corpus = JSON.parse(File.read(corpus_path))
unless corpus["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "behavior corpus lacks observation-level provenance"
end
failures = []
corpus.fetch("observations").each do |item|
  actual = execute(item)
  failures << {"id" => item["id"], "expected" => item["expected"], "actual" => actual} unless equivalent?(actual, item["expected"])
rescue Exception => error
  failures << {"id" => item["id"], "error" => "#{error.class}: #{error.message}"}
end

report = {
  "schemaVersion" => 1,
  "provenance" => corpus.fetch("provenance"),
  "OBSERVATIONS" => corpus.fetch("observations").length,
  "ASSERTIONS" => corpus.fetch("observations").length,
  "FAILURES" => failures.length,
  "provenanceCounts" => corpus.fetch("observations").group_by do |item|
    item.fetch("provenance", "PURE_XNA_DERIVED")
  end.transform_values(&:length).sort.to_h,
  "groupCounts" => corpus.fetch("observations").group_by { |item| behavior_group(item) }.transform_values(&:length).sort.to_h,
  "nativeEvidence" => [
    {
      "group" => "MOUSE_NATIVE", "provenance" => "CNA_NATIVE_INTEGRATION",
      "includedInPureTotals" => false,
      "evidence" => ["test/test_native_integration.rb", "docs/generated/native-stress-report.json",
                     "docs/generated/qualification-report.json"]
    },
    {
      "group" => "GAMEPAD_NATIVE", "provenance" => "CNA_NATIVE_INTEGRATION",
      "includedInPureTotals" => false,
      "evidence" => ["docs/generated/gamepad-native-report.json", "test/test_native_integration.rb",
                     "docs/generated/native-stress-report.json"]
    }
  ],
  "failures" => failures
}
destination = File.expand_path("../docs/generated/behavior-corpus-report.json", __dir__)
File.write(destination, JSON.pretty_generate(report) + "\n")
puts "OBSERVATIONS=#{report["OBSERVATIONS"]}"
puts "ASSERTIONS=#{report["ASSERTIONS"]}"
puts "FAILURES=#{report["FAILURES"]}"
abort JSON.pretty_generate(failures) unless failures.empty?
