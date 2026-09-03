# frozen_string_literal: true

require_relative "../lib/cna"

# The measurements this suite pins, written down **once**.
#
# A pure managed milestone must not grow the Fiddle manifest, and several of this suite's tests say
# exactly that by pinning the census. They used to pin the numbers as literals, in nine separate
# files, which had two costs: a deliberate native milestone had to edit nine unrelated tests, and a
# reader could not tell which literal was the authority. Naming the census once keeps the guard --
# any unintended change to the manifest still fails every one of those tests -- while making an
# intended change a single reviewed edit here.
#
# Update this only together with `docs/native-abi.md` and the compiler-backed
# `docs/generated/native-abi-report.json`, and never to make a red test green.
module NativeSurfaceCensus
  FUNCTIONS = CNA::Native::Manifest::FUNCTIONS.length
  CALLBACKS = CNA::Native::Manifest::CALLBACKS.length
  CONSTANTS = CNA::Native::Manifest::CONSTANTS.length
  LAYOUTS = CNA::Native::Layouts::STRUCTURES.length

  # The census the repository last reviewed. `test_native_abi_gate.rb` compares the two, so this
  # file cannot drift from the manifest silently in either direction.
  REVIEWED = { functions: 390, callbacks: 5, constants: 133, layouts: 63 }.freeze
end

# The strict XNA scoreboard, for exactly the same reason and with exactly the same rule: a milestone
# that completes a type moves these, and a milestone that claims to complete nothing must not.
# Pinning them as literals in a dozen unrelated tests made every completed type a dozen-file edit
# and left no single place a reader could call the authority. `docs/generated/api-compat-report.json`
# is the measurement; this is the reviewed expectation of it.
module ReviewedScoreboard
  TARGET_TYPES = 200
  TARGET_MEMBERS = 2382
  COMPLETE_TYPES = 198
  PARTIAL_TYPES = 2
  MISSING_TYPES = 57
  MISSING_MEMBER = 36
  OVERLOAD_MAPPING_MISMATCH = 15
  # Zero since Foundation 89 projected `GraphicsDevice::Viewport`'s setter. The one entry this
  # carried for its whole history was that property's `"override": { "set": false }`, and it was
  # never a Ruby limitation — see `test_api_verifier.rb`'s inverted guard.
  PROPERTY_MAPPING_MISMATCH = 0
  BCL_PROJECTED_IDENTITIES = 22
  BCL_EXCEPTION_BASES = 2
  BCL_THROWN_EXCEPTIONS = 8
  EVENT_IDENTITIES = 31
  EVENT_OWNER_TYPES = 18
  # `GraphicsDevice`'s projected surface, in one place and for the same reason the counts are in
  # one place: it is still a partial type, so every slice that lands on it moves this list, and five
  # unrelated tests should not each pin it as a literal.
  GRAPHICS_DEVICE_SURFACE = %i[
    IsDisposed Viewport Viewport= Clear Textures VertexTextures SamplerStates VertexSamplerStates
    GraphicsProfile GraphicsDeviceStatus PresentationParameters Present Reset
    BlendState BlendState= DepthStencilState DepthStencilState= RasterizerState RasterizerState=
    BlendFactor BlendFactor= MultiSampleMask MultiSampleMask= ReferenceStencil ReferenceStencil=
    ScissorRectangle ScissorRectangle=
    Indices Indices= SetVertexBuffer SetVertexBuffers GetVertexBuffers
    SetRenderTarget SetRenderTargets GetRenderTargets
    DrawPrimitives DrawIndexedPrimitives DrawInstancedPrimitives
  ].sort.freeze

  # **What the two partial types still owe, named once**, for the same reason the census counts are
  # named once and with a stronger payoff. Ten test files each picked three members as "and these
  # are still absent"; every milestone that closed one therefore edited ten unrelated files, and
  # each of those files was checking a *sample* rather than the set. `outstanding` reads the real
  # remainder out of the strict report, so a test that compares it with the list below asserts the
  # whole thing: a member closed without review fails, and so does one that quietly reappears.
  #
  # Update these together with the milestone that moves them, never to make a red test green.
  GRAPHICS_DEVICE_OUTSTANDING = %w[
    .ctor Adapter DeviceLost DeviceReset DeviceResetting DisplayMode Dispose Disposing
    DrawUserIndexedPrimitives DrawUserPrimitives Finalize GetBackBufferData
    ResourceCreated ResourceDestroyed
  ].sort.freeze

  GRAPHICS_DEVICE_MANAGER_OUTSTANDING = %w[
    CanResetDevice DeviceCreated DeviceDisposing DeviceReset DeviceResetting Dispose Disposed
    FindBestDevice OnDeviceCreated OnDeviceDisposing OnDeviceReset OnDeviceResetting
    OnPreparingDeviceSettings PreparingDeviceSettings RankDevices
  ].sort.freeze

  # The remainder as bare member names, sorted, so a test can compare it with a reviewed list.
  def self.outstanding(strict, name)
    partial_remainder(strict, name).map { |entry| entry[/::([^ ]+) /, 1] }.sort
  end

  # The members a type still owes, or `[]` once the strict report calls it complete.
  #
  # Eight tests assert "the member this milestone added is no longer in `Game`'s partial
  # remainder", each by fetching `partialTypes["…Game"]`. `Game.Content` took `Game` out of the
  # partial register entirely, which is the strongest possible form of that claim and also a
  # `KeyError` for every one of them. Reading the remainder through here keeps each test asserting
  # exactly what it meant, and `assert_complete` states the stronger fact once.
  def self.partial_remainder(strict, name)
    strict.fetch("partialTypes").fetch(name, [])
  end

  def self.complete?(strict, name) = strict.fetch("completeTypeNames").include?(name)
end
