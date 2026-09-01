# frozen_string_literal: true

require "fiddle"
require_relative "../lib/cna"

# What the *loaded artifact* can actually do, measured from it rather than assumed.
#
# CNA's renderer and platform are both build-time selections, so one `libcna_c_api.so` is not
# interchangeable with another: the qualification artifact this suite ran against until Native
# frontier 6 was built `CNA_GRAPHICS_RENDERER=HEADLESS`, whose descriptor sets `needsWindow = false`
# -- CNA's own comment is "No real window, ever -- HEADLESS/SOFTWARE/STUB/PORTABLEGL" -- so it
# creates no window, never acquires the video subsystem, and answers a zero `ClientBounds`, an empty
# screen device name and no focus. Six tests wrote those answers down as literals, which was honest
# for one artifact and wrong for the next: under an `OPENGL33` build the very same binding answers a
# real X11 window, a real client rectangle and a real focus, and those six tests failed.
#
# The literals were never the point. What each of those tests actually asserts is *this binding
# reports the host's answer rather than replacing it with an invention*, and that claim is provable
# against both artifacts as soon as the expectation is measured from the same host. So this module
# measures the environment once per process, through the C ABI, and the tests branch on it.
#
# It deliberately uses raw `Fiddle` rather than growing `CNA::Native::Manifest`. A bound route must
# have a production call site (`docs/native-abi.md`), and none of these questions is one the XNA
# surface asks: `cna_game_window_get_native_window_ext` publishes a backend detail on purpose, for a
# consumer hosting a CNA window inside another toolkit, and this binding does not do that. Measuring
# with the same tool the native-evidence tools use keeps the manifest free of test-only surface.
module RendererEnvironment
  # CNA_NATIVE_WINDOW_SYSTEM_* — the identities this host can produce.
  UNKNOWN = 0
  X11 = 2
  WAYLAND = 3
  NONE = 7
  TERMINAL = 8

  # CNA_RENDERER_FORMAT_USAGE_TEXTURE_STORAGE, the bit `Texture2D`'s constructor needs.
  TEXTURE_STORAGE = 1 << 0

  U64 = Fiddle::TYPE_UINT64_T
  U32 = Fiddle::TYPE_UINT32_T
  PTR = Fiddle::TYPE_VOIDP
  private_constant :U64, :U32, :PTR

  module_function

  def available? = !ENV["CNA_NATIVE_LIBRARY"].to_s.empty?

  # One throwaway game, once per process, taken **before any test runs** -- see the `measurement!`
  # call at the bottom of this file. CNA owns at most one C game per process, so measuring lazily
  # from inside a test that already has one fails; taking the snapshot at load time is what makes
  # the answer available to every test without any of them paying for it.
  def measurement
    return @measurement if defined?(@measurement)

    @measurement = available? ? measure : nil
  end

  def measurement! = measurement

  def renderer_name = measurement&.fetch(:renderer_name)

  # True when this artifact's renderer really creates a native window, which is the single fact the
  # six environment-dependent expectations turn on.
  def windowed? = !measurement.nil? && measurement.fetch(:window_system) != UNKNOWN

  def window_system = measurement&.fetch(:window_system)

  # Whether the active renderer classifies `format` as usable for texture storage. A bit absent from
  # the *known* mask means unknown rather than unsupported, and CNA's header forbids inferring
  # support from the renderer name, so an unclassified format answers `nil`.
  def texture_storage_support(format)
    supports = measurement&.fetch(:format_support)&.fetch(format, nil)
    return nil if supports.nil?
    return nil if (supports.fetch(:known) & TEXTURE_STORAGE).zero?

    !(supports.fetch(:supported) & TEXTURE_STORAGE).zero?
  end

  # The surface formats worth classifying up front: `Color` is what every renderer must carry, and
  # `Bgr565` is the one `Texture2D`'s constructor test asks about. The identities are CNA's, and
  # `CNA_SURFACE_FORMAT_*` happens to agree with XNA's `SurfaceFormat` over this range.
  COLOR = 0
  BGR565 = 1
  CLASSIFIED_FORMATS = { COLOR => "Color", BGR565 => "Bgr565" }.freeze

  def route(name, arguments)
    handle = CNA::Native.library.instance_variable_get(:@handle)
    Fiddle::Function.new(handle[name], arguments, Fiddle::TYPE_UINT32_T)
  end

  def measure
    snapshot = nil
    game = Class.new(Microsoft::Xna::Framework::Game) do
      def initialize(&body)
        @body = body
        super()
        Microsoft::Xna::Framework::GraphicsDeviceManager.new(self)
      end

      def LoadContent
        @captured = @body.call(self, self.GraphicsDevice)
      ensure
        self.Exit
      end

      attr_reader :captured
    end.new { |host, device| snapshot = describe(host, device) }
    begin
      game.Run
    ensure
      game.Dispose
    end
    snapshot
  end

  def describe(game, device)
    device_handle = device.__send__(:native_handle)
    game_handle = game.instance_variable_get(:@host).handle
    {
      renderer_name: renderer_name_of(device_handle),
      window_system: window_system_of(game_handle),
      format_support: CLASSIFIED_FORMATS.keys.to_h { |format| [format, format_support_of(device_handle, format)] }
    }
  end

  def renderer_name_of(device_handle)
    count = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
    route("cna_graphics_device_get_renderer_name_size", [U64, PTR]).call(device_handle, count)
    bytes = count[0, 8].unpack1("Q")
    return "" if bytes.zero?

    buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
    route("cna_graphics_device_copy_renderer_name", [U64, PTR, U64, PTR]).call(device_handle, buffer, bytes, count)
    buffer[0, bytes].force_encoding(Encoding::UTF_8)
  end

  # `CNA_NativeWindowHandle` is 48 bytes: two uint32 header words, the system identity, three
  # pointers and the X11 XID. Only the identity is read here; the pointers are borrowed and this
  # binding has no business holding one.
  def window_system_of(game_handle)
    handle = Fiddle::Pointer.malloc(48, Fiddle::RUBY_FREE)
    handle[0, 48] = "\0" * 48
    route("cna_native_window_handle_init", [PTR]).call(handle)
    result = route("cna_game_window_get_native_window_ext", [U64, PTR]).call(game_handle, handle)
    return UNKNOWN unless result.zero?

    handle[8, 4].unpack1("L")
  end

  def format_support_of(device_handle, format)
    known = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
    supported = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
    known[0, 4] = "\0" * 4
    supported[0, 4] = "\0" * 4
    result = route("cna_graphics_device_get_surface_format_support_ext", [U64, U32, PTR, PTR])
             .call(device_handle, format, known, supported)
    return { known: 0, supported: 0 } unless result.zero?

    { known: known[0, 4].unpack1("L"), supported: supported[0, 4].unpack1("L") }
  end
end

# Taken now, while nothing else in the process owns a CNA game.
RendererEnvironment.measurement!
