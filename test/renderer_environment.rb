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

    @measurement = available? ? measure_safely : nil
  end

  def measurement! = measurement

  # The measurement must never take the suite down with it. A windowed renderer acquires the video
  # subsystem, and on this host a **fresh X connection per game** is a finite resource: creating and
  # destroying tens of games against one X server intermittently fails inside SDL with
  # `AcquireSubsystem(Video) failed: x11 not available`, and the failure survives into the next
  # process. That is an environment limit rather than a defect in this binding -- one long-lived
  # game is unaffected, 600 frames in a row -- so an unmeasurable environment is reported as
  # unmeasured, every renderer-conditional test skips and says why, and everything else still runs.
  def measure_safely
    measure
  rescue CNA::NativeError => error
    warn "renderer environment unmeasurable: #{error.message}"
    nil
  end

  def renderer_name = measurement&.fetch(:renderer_name)

  # Whether this artifact's renderer really has volume and cube-face storage, measured by using it
  # rather than by reading a flag: a one-texel round trip through the same public members a consumer
  # would call. HEADLESS refuses both -- `cna_texture3d_create` with "this renderer does not support
  # real volume (3D) texture storage" and `cna_texturecube_set_data` with "did not store the
  # complete requested cube face region" -- while `OPENGL33` round-trips both exactly.
  def volume_storage? = measurement&.fetch(:volume_storage) || false

  def cube_face_storage? = measurement&.fetch(:cube_face_storage) || false

  # `CNA_GRAPHICS_CAPABILITY_COMPILED_EFFECTS`. Compiled Effect Framework bytecode needs the
  # MojoShader runtime, which is a **fetched dependency** the EasyGL, SDL_GPU and Vulkan families
  # only carry when their build option is on, so the capability never claims more than the binary
  # contains. It is false on the HEADLESS and OPENGL33 artifacts and true on the OPENGLES3 one
  # built `-DCNA_EASYGL_COMPILED_EFFECTS=ON`.
  COMPILED_EFFECTS = 13

  def compiled_effects? = measurement&.fetch(:compiled_effects) || false

  # The compiled-effect fixture, referenced **by path** through an environment variable the way the
  # XACT and XNB fixtures are, and never copied into this repository.
  def effect_fixture
    path = ENV["CNA_TEST_FX"]
    path if path && File.file?(path)
  end

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

      # In `Draw`, not `LoadContent`: a renderer's frame is what `BeginDraw`/`EndDraw` open and
      # close, and work issued outside one can report success and do nothing.
      def Draw(_time)
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
      format_support: CLASSIFIED_FORMATS.keys.to_h { |format| [format, format_support_of(device_handle, format)] },
      volume_storage: volume_storage_of(device),
      cube_face_storage: cube_face_storage_of(device),
      compiled_effects: capability_of(device_handle, COMPILED_EFFECTS)
    }
  end

  def capability_of(device_handle, capability)
    supported = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
    supported[0, 4] = "\0" * 4
    result = route("cna_graphics_device_supports_capability", [U64, U32, PTR])
             .call(device_handle, capability, supported)
    result.zero? && supported[0, 4].unpack1("L") == 1
  end

  G = Microsoft::Xna::Framework::Graphics
  C = Microsoft::Xna::Framework::Color
  private_constant :G, :C

  def volume_storage_of(device)
    texture = G::Texture3D.new(device, 1, 1, 1, false, G::SurfaceFormat::Color)
    begin
      texture.SetData(C, [C.new(1, 2, 3, 4)])
      read = [C.new(0, 0, 0, 0)]
      texture.GetData(C, read)
      read.first == C.new(1, 2, 3, 4)
    ensure
      texture.Dispose
    end
  rescue CNA::CapabilityError
    false
  end

  def cube_face_storage_of(device)
    texture = G::TextureCube.new(device, 1, false, G::SurfaceFormat::Color)
    begin
      texture.SetData(C, G::CubeMapFace::PositiveX, [C.new(5, 6, 7, 8)])
      read = [C.new(0, 0, 0, 0)]
      texture.GetData(C, G::CubeMapFace::PositiveX, read)
      read.first == C.new(5, 6, 7, 8)
    ensure
      texture.Dispose
    end
  rescue CNA::CapabilityError
    false
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
