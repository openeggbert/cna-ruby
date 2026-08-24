# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

EXPECTED_SHA256 = "7207908eb7926cc90a156d0370c907add4dda465421cea1cbec51afba2f97fdc"
source = ARGV.fetch(0) { abort "usage: import_reference.rb PATH" }
bytes = File.binread(source)
abort "reference SHA-256 mismatch" unless Digest::SHA256.hexdigest(bytes) == EXPECTED_SHA256
contract = JSON.parse(bytes)
types = contract.fetch("types")
members = types.sum { |type| type.fetch("members").length }
abort "reference count mismatch" unless types.length == 257 && members == 2964

destination = File.expand_path("reference/xna40-windows-runtime-contract.json", __dir__)
FileUtils.mkdir_p(File.dirname(destination))
File.binwrite(destination, bytes)
puts "REFERENCE_TYPES=257"
puts "REFERENCE_MEMBERS=2964"
puts "REFERENCE_SHA256=#{EXPECTED_SHA256}"
