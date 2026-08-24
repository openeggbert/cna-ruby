# frozen_string_literal: true

require "json"

reference_path = File.expand_path("reference/xna40-windows-runtime-contract.json", __dir__)
selection_path = File.expand_path("selection.json", __dir__)
reference = JSON.parse(File.read(reference_path))
selection = JSON.parse(File.read(selection_path))

def enum_storage?(type, member)
  type.fetch("kind") == "enum" && member.fetch("name") == "value__"
end

def parameters(member)
  member.fetch("parameters", []).map { |parameter| parameter.fetch("type") }
end

def match?(member, selector)
  return false if selector["kind"] && selector["kind"] != member["kind"]
  return false if selector["name"] && selector["name"] != member["name"]
  return false if selector.key?("static") && selector["static"] != member["static"]
  return false if selector["parameters"] && selector["parameters"] != parameters(member)
  true
end

types_by_name = reference.fetch("types").to_h { |type| [type.fetch("name"), type] }
target_types = selection.fetch("types").map do |type_selection|
  reference_type = types_by_name.fetch(type_selection.fetch("name"))
  candidates = reference_type.fetch("members").reject { |member| enum_storage?(reference_type, member) }
  members = if type_selection["complete"]
              candidates
            else
              selected = []
              if type_selection["includeNonRefOut"]
                selected.concat(candidates.reject do |member|
                  type_selection.fetch("excludeNames", []).include?(member["name"]) ||
                    member.fetch("parameters", []).any? { |parameter| parameter["ref"] || parameter["out"] }
                end)
              end
              type_selection.fetch("include", []).each do |selector|
                matches = candidates.select { |member| match?(member, selector) }
                abort "selector matched nothing for #{reference_type["name"]}: #{selector}" if matches.empty?
                matches.each do |member|
                  copy = Marshal.load(Marshal.dump(member))
                  selector.fetch("override", {}).each { |key, value| copy[key] = value }
                  selected << copy
                end
              end
              exclusions = type_selection.fetch("exclude", [])
              selected.reject { |member| exclusions.any? { |selector| match?(member, selector) } }
            end
  member_keys = members.map { |member| [member["kind"], member["name"], member["static"], parameters(member)] }
  abort "duplicate target member in #{reference_type["name"]}" unless member_keys.uniq.length == member_keys.length
  reference_type.merge("members" => members, "rubyName" => reference_type.fetch("name").gsub(".", "::"))
end

result = {
  "schemaVersion" => 1,
  "profile" => reference.fetch("profile"),
  "sourceReferenceSha256" => "7207908eb7926cc90a156d0370c907add4dda465421cea1cbec51afba2f97fdc",
  "types" => target_types
}
File.write(File.expand_path("signatures.json", __dir__), JSON.pretty_generate(result) + "\n")
puts "TARGET_TYPES=#{target_types.length}"
puts "TARGET_MEMBERS=#{target_types.sum { |type| type.fetch("members").length }}"
