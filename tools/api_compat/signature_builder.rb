# frozen_string_literal: true

require "json"
require_relative "name_mapper"

# The target surface, derived from `selection.json` and the pinned reference contract.
#
# Extracted from `build_signatures.rb` so the derivation can be *checked* without writing a file.
# It had to be: `selection.json` is meant to be the reviewed statement of what this binding targets,
# and it had stopped being the source of `signatures.json` — five types' member lists were maintained
# only in the generated file, and twenty-three whole types were never in the selection at all, so
# running the generator would have deleted 237 members and nothing would have noticed. That is the
# fourth artifact in this project to drift from the tool that claims to produce it, after the
# dependency frontier, the behaviour corpus's authoring files and `plan.md`'s deferred boundaries.
# `test/test_signature_selection.rb` now compares the two on every run.
module CNAApiCompat
  module SignatureBuilder
    module_function

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

    def reference_path = File.expand_path("reference/xna40-windows-runtime-contract.json", __dir__)
    def selection_path = File.expand_path("selection.json", __dir__)
    def signatures_path = File.expand_path("signatures.json", __dir__)

    def build(reference: JSON.parse(File.read(reference_path)),
              selection: JSON.parse(File.read(selection_path)))
      types_by_name = reference.fetch("types").to_h { |type| [type.fetch("name"), type] }
      target_types = selection.fetch("types").map do |type_selection|
        reference_type = types_by_name.fetch(type_selection.fetch("name"))
        members = select_members(reference_type, type_selection)
        member_keys = members.map { |member| [member["kind"], member["name"], member["static"], parameters(member)] }
        raise "duplicate target member in #{reference_type["name"]}" unless member_keys.uniq.length == member_keys.length

        reference_type.merge(
          "members" => members,
          "rubyName" => CNAApiCompat::NameMapper.runtime_constant_path(reference_type.fetch("name"))
        )
      end

      {
        "schemaVersion" => 1,
        "profile" => reference.fetch("profile"),
        "sourceReferenceSha256" => "7207908eb7926cc90a156d0370c907add4dda465421cea1cbec51afba2f97fdc",
        "languageTypeMappings" => {
          "System.IntPtr" => {
            "rubyType" => "Integer", "signed" => true, "width" => "native-pointer",
            "nativeBoundary" => "fixed-width unsigned C carrier containing the signed pointer bit pattern"
          }
        },
        "types" => target_types
      }
    end

    def select_members(reference_type, type_selection)
      candidates = reference_type.fetch("members").reject { |member| enum_storage?(reference_type, member) }
      return candidates if type_selection["complete"]

      selected = []
      if type_selection["includeNonRefOut"]
        selected.concat(candidates.reject do |member|
          type_selection.fetch("excludeNames", []).include?(member["name"]) ||
            member.fetch("parameters", []).any? { |parameter| parameter["ref"] || parameter["out"] }
        end)
      end
      type_selection.fetch("include", []).each do |selector|
        matches = candidates.select { |member| match?(member, selector) }
        raise "selector matched nothing for #{reference_type["name"]}: #{selector}" if matches.empty?

        matches.each do |member|
          copy = Marshal.load(Marshal.dump(member))
          selector.fetch("override", {}).each { |key, value| copy[key] = value }
          selected << copy
        end
      end
      exclusions = type_selection.fetch("exclude", [])
      selected.reject { |member| exclusions.any? { |selector| match?(member, selector) } }
    end

    def serialize(result) = JSON.pretty_generate(result) + "\n"
  end
end
