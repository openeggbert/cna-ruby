# frozen_string_literal: true

require_relative "../lib/cna"

# The size of the native boundary, written down **once**.
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
  REVIEWED = { functions: 68, callbacks: 3, constants: 65, layouts: 18 }.freeze
end
