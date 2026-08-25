# frozen_string_literal: true

require "json"
require_relative "../lib/cna"
require_relative "capability_consistency"

root = File.expand_path("..", __dir__)
source = File.join(root, "docs", "runtime-capabilities.json")
data = JSON.parse(File.read(source))

def optional_json(path) = File.exist?(path) ? JSON.parse(File.read(path)) : nil

strict = optional_json(File.join(root, "docs", "generated", "api-compat-report.json"))
inventory = optional_json(File.join(root, "docs", "generated", "xna-il-inventory.json"))
signatures = optional_json(File.join(root, "tools", "api_compat", "signatures.json"))

# The registry is generated only from a registry that agrees with the rest of the project. Nothing
# measured it through Foundation 27, which is how three resolved blockers survived as active
# decisions in a milestone that reported fully green.
contradictions = []
if strict
  namespaces = CapabilityConsistency.framework_namespaces(
    types: signatures ? CapabilityConsistency.projected_types(signatures) : []
  )
  contradictions = CapabilityConsistency.check(
    registry: data, strict: strict, il_inventory: inventory, namespaces: namespaces
  )
end

lines = ["# Runtime capabilities", "", "| Capability | Category | Status | Evidence |", "| --- | --- | --- | --- |"]
data.fetch("capabilities").each do |row|
  lines << "| `#{row["id"]}` | #{row["category"]} | #{row["status"]} | #{row["evidence"] || "—"} |"
end

unless contradictions.empty?
  warn "capability registry contradicts measured project state; refusing to generate"
  contradictions.each { |finding| warn "  #{finding}" }
  puts "CAPABILITIES=#{data.fetch("capabilities").length}"
  puts "CAPABILITY_CONTRADICTIONS=#{contradictions.length}"
  exit 1
end

File.write(File.join(root, "docs", "generated", "runtime-capabilities.md"), lines.join("\n") + "\n")
puts "CAPABILITIES=#{data.fetch("capabilities").length}"
puts "CAPABILITY_CONTRADICTIONS=#{contradictions.length}"
