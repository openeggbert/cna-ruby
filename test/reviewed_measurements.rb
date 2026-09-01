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
  REVIEWED = { functions: 146, callbacks: 5, constants: 71, layouts: 24 }.freeze
end

# The strict XNA scoreboard, for exactly the same reason and with exactly the same rule: a milestone
# that completes a type moves these, and a milestone that claims to complete nothing must not.
# Pinning them as literals in a dozen unrelated tests made every completed type a dozen-file edit
# and left no single place a reader could call the authority. `docs/generated/api-compat-report.json`
# is the measurement; this is the reviewed expectation of it.
module ReviewedScoreboard
  TARGET_TYPES = 157
  TARGET_MEMBERS = 1913
  COMPLETE_TYPES = 152
  PARTIAL_TYPES = 5
  MISSING_TYPES = 100
  MISSING_MEMBER = 107
  BCL_PROJECTED_IDENTITIES = 17
  BCL_EXCEPTION_BASES = 2
  BCL_THROWN_EXCEPTIONS = 8
  EVENT_IDENTITIES = 22
  EVENT_OWNER_TYPES = 9
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
