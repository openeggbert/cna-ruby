# frozen_string_literal: true

require "json"

source = File.expand_path("../docs/runtime-capabilities.json", __dir__)
data = JSON.parse(File.read(source))
lines = ["# Runtime capabilities", "", "| Capability | Category | Status | Evidence |", "| --- | --- | --- | --- |"]
data.fetch("capabilities").each do |row|
  lines << "| `#{row["id"]}` | #{row["category"]} | #{row["status"]} | #{row["evidence"] || "—"} |"
end
File.write(File.expand_path("../docs/generated/runtime-capabilities.md", __dir__), lines.join("\n") + "\n")
puts "CAPABILITIES=#{data.fetch("capabilities").length}"
