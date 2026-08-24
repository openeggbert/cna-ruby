#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"
require_relative "../lib/cna"

PV = Microsoft::Xna::Framework::Graphics::PackedVector
OUTPUT = Pathname(__dir__).join("..", "docs", "generated", "packed-vector-exhaustive-report.json").expand_path

def timed_sweep(name, iterations)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  failures = yield
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  {
    "name" => name,
    "iterations" => iterations,
    "failures" => failures,
    "seconds" => elapsed.round(6)
  }
end

def repack_sweep(type, packed_values, conversion)
  failures = 0
  packed_values.each do |bits|
    value = type.allocate
    value.PackedValue = bits
    reconstructed = type.new(*conversion.call(value))
    failures += 1 unless reconstructed.PackedValue == bits
  end
  failures
end

sweeps = []
sweeps << timed_sweep("Alpha8", 256) do
  failures = 0
  256.times do |bits|
    value = PV::Alpha8.allocate
    value.PackedValue = bits
    failures += 1 unless PV::Alpha8.new(value.ToAlpha).PackedValue == bits
  end
  failures
end

sweeps << timed_sweep("Bgr565", 65_536) do
  repack_sweep(PV::Bgr565, 0..0xffff, lambda { |value|
    vector = value.ToVector3
    [vector.X, vector.Y, vector.Z]
  })
end

sweeps << timed_sweep("Bgra4444", 65_536) do
  repack_sweep(PV::Bgra4444, 0..0xffff, lambda { |value|
    vector = value.ToVector4
    [vector.X, vector.Y, vector.Z, vector.W]
  })
end

sweeps << timed_sweep("Bgra5551", 65_536) do
  repack_sweep(PV::Bgra5551, 0..0xffff, lambda { |value|
    vector = value.ToVector4
    [vector.X, vector.Y, vector.Z, vector.W]
  })
end

classification = {"zero" => 0, "subnormal" => 0, "normal" => 0, "infinity" => 0, "nan" => 0}
sweeps << timed_sweep("HalfSingle", 65_536) do
  failures = 0
  65_536.times do |bits|
    exponent = (bits >> 10) & 0x1f
    fraction = bits & 0x03ff
    category = if exponent.zero?
                 fraction.zero? ? "zero" : "subnormal"
               elsif exponent == 0x1f
                 fraction.zero? ? "infinity" : "nan"
               else
                 "normal"
               end
    classification[category] += 1
    value = PV::HalfSingle.allocate
    value.PackedValue = bits
    decoded = value.ToSingle
    failures += 1 unless decoded.finite?
    failures += 1 unless PV::HalfSingle.new(decoded).PackedValue == bits
  end
  failures
end

report = {
  "schemaVersion" => 1,
  "provenance" => "XNA-derived semantic round-trip sweeps; expected classifications come from the 16-bit encoding fields, not production packing tables",
  "sweeps" => sweeps,
  "halfClassification" => classification,
  "TOTAL_ITERATIONS" => sweeps.sum { |sweep| sweep.fetch("iterations") },
  "FAILURES" => sweeps.sum { |sweep| sweep.fetch("failures") },
  "TOTAL_SECONDS" => sweeps.sum { |sweep| sweep.fetch("seconds") }.round(6)
}
OUTPUT.dirname.mkpath
OUTPUT.write(JSON.pretty_generate(report) + "\n")

puts "EXHAUSTIVE_ITERATIONS=#{report.fetch("TOTAL_ITERATIONS")}"
puts "EXHAUSTIVE_FAILURES=#{report.fetch("FAILURES")}"
puts "EXHAUSTIVE_SECONDS=#{format("%.6f", report.fetch("TOTAL_SECONDS"))}"
exit(report.fetch("FAILURES").zero? ? 0 : 1)
