# frozen_string_literal: true

# Native frontier 6 — qualifying this binding against a CNA artifact whose renderer really renders.
#
# Every measurement this binding had made until now came from one artifact built
# `CNA_GRAPHICS_RENDERER=HEADLESS`, and `docs/graphics-adapter-audit-evidence.md` recorded the
# consequence: "the single largest lever is a qualification artifact with a real renderer". This
# tool is what measures whether that is true, against an artifact that has one.
#
# It writes CNA output, so nothing it produces may enter the behaviour corpus, which is
# `never CNA output` by construction. It is native evidence, in the shape
# `run_gamepad_native_evidence.rb` established, and it is deliberately runnable against *any*
# artifact: the HEADLESS one answers the same questions differently, and the difference is the
# evidence.
#
#     CNA_NATIVE_LIBRARY=~/deps/cna-c-abi-0.21.0-opengl33/libcna_c_api.so \
#     DISPLAY=:77 SDL_VIDEODRIVER=x11 ruby tools/run_renderer_qualification.rb
#
# `RENDERER_QUALIFICATION_FRAMES` overrides the long stability run (default 600).

require "json"
require "digest"
require "fiddle"
require_relative "../lib/cna"

abort "CNA_NATIVE_LIBRARY is required" unless ENV["CNA_NATIVE_LIBRARY"]

F = Microsoft::Xna::Framework
G = Microsoft::Xna::Framework::Graphics

LIBRARY = CNA::Native.library
HANDLE = LIBRARY.instance_variable_get(:@handle)
U64 = Fiddle::TYPE_UINT64_T
U32 = Fiddle::TYPE_UINT32_T
I32 = Fiddle::TYPE_INT32_T
PTR = Fiddle::TYPE_VOIDP

def route(name, arguments)
  Fiddle::Function.new(HANDLE[name], arguments, Fiddle::TYPE_UINT32_T)
end

def zeroed(bytes, struct_size = bytes, version = 1)
  pointer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
  pointer[0, bytes] = "\0" * bytes
  pointer[0, 8] = [struct_size, version].pack("LL")
  pointer
end

def counted_string(symbol_size, symbol_copy, *leading)
  count = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
  route(symbol_size, [U64] * leading.length + [PTR]).call(*leading, count)
  bytes = count[0, 8].unpack1("Q")
  return "" if bytes.zero?

  buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
  route(symbol_copy, [U64] * leading.length + [PTR, U64, PTR]).call(*leading, buffer, bytes, count)
  buffer[0, bytes].force_encoding(Encoding::UTF_8)
end

# ------------------------------------------------------------------ the one game every probe uses

# The body runs inside `Draw`, not `LoadContent`. A renderer's frame is what `BeginDraw`/`EndDraw`
# open and close, and a clear issued outside one has no target to land on -- measured: the same
# render-target probe run from `LoadContent` reads back transparent black on `OPENGL33` while the
# clear, the bind and the readback all report success.
class QualificationGame < F::Game
  attr_reader :captured

  def initialize(&body)
    @body = body
    @captured = nil
    super()
    F::GraphicsDeviceManager.new(self)
  end

  def Draw(_time)
    @captured = @body.call(self, self.GraphicsDevice)
  ensure
    self.Exit
  end
end

def with_device
  game = QualificationGame.new { |host, device| yield(host, device) }
  begin
    game.Run
  ensure
    game.Dispose
  end
  game.captured
end

# ------------------------------------------------------------------------------- renderer identity

def renderer_identity(game, device)
  device_handle = device.__send__(:native_handle)
  game_handle = game.instance_variable_get(:@host).handle

  # `CNA_RendererInfo` is two uint32 header words, a uint64 name length, a uint64 capability bit
  # set, then the renderer type and the maximum texture dimension.
  info = zeroed(32)
  info_result = route("cna_graphics_device_get_renderer_info", [U64, PTR]).call(device_handle, info)
  fields = info[0, 32].unpack("LLQQLL")

  native_window = zeroed(48, 0, 0)
  route("cna_native_window_handle_init", [PTR]).call(native_window)
  window_result = route("cna_game_window_get_native_window_ext", [U64, PTR]).call(game_handle, native_window)
  window = native_window[0, 48].unpack("LLLLQQQQ")

  bounds = zeroed(16, 0, 0)
  bounds_result = route("cna_game_window_get_client_bounds", [U64, PTR]).call(game_handle, bounds)

  {
    "rendererInfoResult" => info_result,
    "rendererName" => counted_string("cna_graphics_device_get_renderer_name_size",
                                     "cna_graphics_device_copy_renderer_name", device_handle),
    "capabilityFlags" => fields[3],
    "rendererType" => fields[4],
    "maxTextureDimension" => fields[5],
    "nativeWindowResult" => window_result,
    "nativeWindowSystem" => window[2],
    "nativeWindowHasDisplayPointer" => !window[4].zero?,
    "nativeWindowXid" => window[7],
    "clientBoundsResult" => bounds_result,
    "clientBounds" => bounds[0, 16].unpack("llll"),
    "screenDeviceName" => counted_string("cna_game_window_get_screen_device_name_size",
                                         "cna_game_window_copy_screen_device_name", game_handle),
    "capabilities" => (0..18).to_h do |capability|
      supported = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
      supported[0, 4] = "\0" * 4
      result = route("cna_graphics_device_supports_capability", [U64, U32, PTR])
               .call(device_handle, capability, supported)
      [capability.to_s, result.zero? ? supported[0, 4].unpack1("L") == 1 : nil]
    end
  }
end

# ------------------------------------------------------------------------------------- the adapter

# The two adapter string routes have no separate size query: a null destination with zero capacity
# is the count query, which is what `display.h` documents.
def adapter_string(symbol, device_handle, index)
  count = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
  count[0, 8] = "\0" * 8
  route(symbol, [U64, U32, PTR, U64, PTR]).call(device_handle, index, nil, 0, count)
  bytes = count[0, 8].unpack1("Q")
  return "" if bytes.zero?

  buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
  route(symbol, [U64, U32, PTR, U64, PTR]).call(device_handle, index, buffer, bytes, count)
  buffer[0, bytes].force_encoding(Encoding::UTF_8)
end

def adapter_snapshot(device)
  device_handle = device.__send__(:native_handle)
  count = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
  count_result = route("cna_graphics_adapter_get_count", [U64, PTR]).call(device_handle, count)
  adapters = count[0, 8].unpack1("Q")

  mode = zeroed(24)
  mode_result = route("cna_graphics_adapter_get_current_display_mode", [U64, U32, PTR])
                .call(device_handle, 0, mode)
  current = mode[0, 24].unpack("LLllfL")

  modes_count = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
  route("cna_graphics_adapter_get_display_mode_count", [U64, U32, U32, U32, PTR])
    .call(device_handle, 0, 0, 0, modes_count)
  supported = modes_count[0, 8].unpack1("Q")
  modes = []
  if supported.positive?
    buffer = Fiddle::Pointer.malloc(24 * supported, Fiddle::RUBY_FREE)
    buffer[0, 24 * supported] = "\0" * (24 * supported)
    supported.times { |index| buffer[24 * index, 8] = [24, 1].pack("LL") }
    route("cna_graphics_adapter_copy_display_modes", [U64, U32, U32, U32, PTR, U64, PTR])
      .call(device_handle, 0, 0, 0, buffer, supported, modes_count)
    supported.times do |index|
      fields = buffer[24 * index, 24].unpack("LLllfL")
      modes << { "width" => fields[2], "height" => fields[3], "format" => fields[5] }
    end
  end

  info = zeroed(48)
  route("cna_graphics_adapter_get_info", [U64, U32, PTR]).call(device_handle, 0, info)
  described = info[0, 48].unpack("LLLCCCCllll")

  monitor = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
  monitor[0, 8] = "\0" * 8

  {
    "countResult" => count_result,
    "count" => adapters,
    "description" => adapter_string("cna_graphics_adapter_copy_description", device_handle, 0),
    "deviceName" => adapter_string("cna_graphics_adapter_copy_device_name", device_handle, 0),
    "isDefaultAdapter" => described[3] == 1,
    "isWideScreen" => described[4] == 1,
    "vendorId" => described[7],
    "deviceId" => described[8],
    "revision" => described[9],
    "subSystemId" => described[10],
    "currentDisplayModeResult" => mode_result,
    "currentDisplayMode" => { "width" => current[2], "height" => current[3],
                              "aspectRatio" => current[4], "format" => current[5] },
    "supportedDisplayModes" => modes,
    "monitorHandleResult" => route("cna_graphics_adapter_get_native_monitor_handle", [U64, U32, PTR])
                             .call(device_handle, 0, monitor),
    "refreshResult" => route("cna_graphics_adapters_refresh", [U64]).call(device_handle)
  }
end

# ------------------------------------------------------- the graphics semantic: draw, then read it

# The render target is created, bound, cleared to a colour nothing else would produce, unbound and
# read back through the same `cna_texture2d_get_data` route `Texture2D.GetData` uses. A backend with
# no real off-screen storage reports `renderer_available` false and refuses the bind, which is why
# both are recorded rather than assumed.
CLEAR = { r: 0.25, g: 0.5, b: 0.75, a: 1.0 }.freeze
TARGET_WIDTH = 8
TARGET_HEIGHT = 4

def render_target_readback(device)
  device_handle = device.__send__(:native_handle)
  create = zeroed(40)
  create[8, 8] = [TARGET_WIDTH, TARGET_HEIGHT].pack("LL")
  create[16, 4] = [0].pack("L")           # mip_map false
  create[20, 4] = [0].pack("L")           # format Color
  create[24, 4] = [0].pack("L")           # depth format None
  create[28, 4] = [0].pack("l")           # multi sample count
  create[32, 4] = [0].pack("L")           # usage DiscardContents
  create[36, 4] = [0].pack("L")           # reserved1
  output = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
  output[0, 8] = "\0" * 8
  create_result = route("cna_render_target2d_create", [U64, PTR, PTR]).call(device_handle, create, output)
  target = output[0, 8].unpack1("Q")
  return { "createResult" => create_result, "created" => false } unless create_result.zero? && !target.zero?

  info = zeroed(48)
  info_result = route("cna_render_target_get_info", [U64, PTR]).call(target, info)
  # `CNA_RenderTargetInfo`: header, kind, width, height, level count, format, depth format,
  # multisample count, usage, then the two flags -- content lost first, renderer availability
  # second.
  described = info[0, 48].unpack("LLLLLLLLlLCC")
  available = described[11] == 1

  bind_result = route("cna_graphics_device_set_render_target2d", [U64, U64]).call(device_handle, target)
  clear_result = route("cna_graphics_device_clear_rgba", [U64, Fiddle::TYPE_FLOAT, Fiddle::TYPE_FLOAT,
                                                          Fiddle::TYPE_FLOAT, Fiddle::TYPE_FLOAT])
                 .call(device_handle, CLEAR[:r], CLEAR[:g], CLEAR[:b], CLEAR[:a])
  unbind_result = route("cna_graphics_device_set_render_target2d", [U64, U64]).call(device_handle, 0)

  pixels = TARGET_WIDTH * TARGET_HEIGHT
  transfer = zeroed(48)
  transfer[8, 8] = [0, 0].pack("lL")
  transfer[32, 16] = [0, pixels].pack("QQ")
  destination = Fiddle::Pointer.malloc(4 * pixels, Fiddle::RUBY_FREE)
  destination[0, 4 * pixels] = "\0" * (4 * pixels)
  written = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
  written[0, 8] = "\0" * 8
  read_result = route("cna_texture2d_get_data", [U64, U32, PTR, PTR, U64, PTR])
                .call(target, 0, transfer, destination, pixels, written)
  read = destination[0, 4 * pixels].unpack("C*")
  route("cna_render_target_destroy", [U64]).call(target)

  {
    "createResult" => create_result,
    "created" => true,
    "infoResult" => info_result,
    "width" => described[3],
    "height" => described[4],
    "isContentLost" => described[10] == 1,
    "rendererAvailable" => available,
    "format" => described[6],
    "levelCount" => described[5],
    "bindResult" => bind_result,
    "clearResult" => clear_result,
    "unbindResult" => unbind_result,
    "readResult" => read_result,
    "elementsWritten" => written[0, 8].unpack1("Q"),
    "clearedTo" => [(CLEAR[:r] * 255).round, (CLEAR[:g] * 255).round, (CLEAR[:b] * 255).round, 255],
    "firstPixel" => read.first(4),
    "allPixelsEqual" => read.each_slice(4).to_a.uniq.length == 1
  }
end

# --------------------------------------------------------------------------------- frame stability

# One game, N frames, each with a real `Clear` inside `Draw`. The point is that the loop survives:
# the renderer presents, the window pumps its events and nothing accumulates.
class FrameGame < F::Game
  attr_reader :frames, :error

  def initialize(target)
    @target = target
    @frames = 0
    @error = nil
    super()
    F::GraphicsDeviceManager.new(self)
  end

  def Draw(_time)
    self.GraphicsDevice.Clear(F::Color.new(16, 32, 48))
    @frames += 1
    self.Exit if @frames >= @target
  rescue StandardError => error
    @error ||= "#{error.class}: #{error.message}"
    self.Exit
  end
end

def frame_run(target)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  game = FrameGame.new(target)
  begin
    game.Run
  rescue StandardError => error
    return { "requested" => target, "completed" => game.frames, "error" => "#{error.class}: #{error.message}" }
  ensure
    game.Dispose
  end
  {
    "requested" => target,
    "completed" => game.frames,
    "error" => game.error,
    "seconds" => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)
  }
end

# ------------------------------------------------------------------------------------------ report

artifact = ENV.fetch("CNA_NATIVE_LIBRARY")
long_frames = Integer(ENV.fetch("RENDERER_QUALIFICATION_FRAMES", "600"))

identity, adapters, readback = with_device do |game, device|
  [renderer_identity(game, device), adapter_snapshot(device), render_target_readback(device)]
end

# The finding this report exists to make undeniable, and it needs no SDL and no second process.
#
# In one frame, with one device, two canonical routes disagree about whether this host has a
# display: `cna_game_window_copy_screen_device_name` answers the display's real name, while
# `cna_graphics_adapter_copy_description` answers CNA's no-display fallback, "Default Display", with
# its fabricated 800x480 mode. The adapter list is a static cache filled by
# `GraphicsAdapter::getDefaultAdapterProperty()` -- evaluated as an *argument* of
# `GraphicsDevice::GraphicsDevice()`, which is before `createOrAttachWindow()` acquires the video
# subsystem -- and `cna_graphics_adapters_refresh` refuses by design, so nothing a C consumer can
# call ever corrects it.
FALLBACK_DESCRIPTION = "Default Display"
FALLBACK_MODE = [800, 480].freeze

conflict = {
  "windowReportsADisplayNamed" => identity.fetch("screenDeviceName"),
  "adapterReportsDescription" => adapters.fetch("description"),
  "adapterReportsCurrentMode" => [adapters.dig("currentDisplayMode", "width"),
                                  adapters.dig("currentDisplayMode", "height")],
  "adapterIsTheNoDisplayFallback" => adapters.fetch("description") == FALLBACK_DESCRIPTION &&
    [adapters.dig("currentDisplayMode", "width"), adapters.dig("currentDisplayMode", "height")] == FALLBACK_MODE,
  "windowHasANativeSurface" => identity.fetch("nativeWindowSystem") != 0,
  "refreshRefused" => adapters.fetch("refreshResult") != 0
}
conflict["adapterContradictsTheWindow"] =
  conflict.fetch("windowHasANativeSurface") && conflict.fetch("adapterIsTheNoDisplayFallback")

run = {
  "artifact" => {
    "path" => artifact,
    "bytes" => File.size(artifact),
    "sha256" => Digest::SHA256.file(artifact).hexdigest
  },
  "environment" => {
    "DISPLAY" => ENV["DISPLAY"],
    "WAYLAND_DISPLAY" => ENV["WAYLAND_DISPLAY"],
    "SDL_VIDEODRIVER" => ENV["SDL_VIDEODRIVER"]
  },
  "renderer" => identity,
  "adapter" => adapters,
  "displayEvidenceConflict" => conflict,
  "renderTarget" => readback,
  "frames" => { "short" => frame_run(60), "long" => frame_run(long_frames) }
}

# One file, one entry per renderer, so the two artifacts' answers sit side by side: the difference
# between them is the evidence, and neither run can quietly overwrite the other.
path = File.expand_path("../docs/generated/renderer-native-report.json", __dir__)
existing = File.file?(path) ? JSON.parse(File.read(path)) : {}
runs = existing.fetch("runs", {})
runs[identity.fetch("rendererName")] = run
report = {
  "schemaVersion" => 1,
  "CNA_NATIVE_EVIDENCE" => true,
  "runs" => runs.sort.to_h
}
File.write(path, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(run)
