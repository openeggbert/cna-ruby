# frozen_string_literal: true

require "json"

root = File.expand_path("../..", __dir__)
reference = JSON.parse(File.read(File.join(__dir__, "reference", "xna40-windows-runtime-contract.json")))
target = JSON.parse(File.read(File.join(__dir__, "signatures.json")))
strict = JSON.parse(File.read(File.join(root, "docs", "generated", "api-compat-report.json")))

reference_by_name = reference.fetch("types").to_h { |type| [type.fetch("name"), type] }
target_names = target.fetch("types").map { |type| type.fetch("name") }
complete_names = strict.fetch("completeTypeNames")

extract_types = lambda do |signature|
  next [] unless signature

  reference_by_name.keys.select do |name|
    signature == name || signature.include?("[#{name}") || signature.include?(",#{name}") ||
      signature.include?("#{name}]") || signature.include?("#{name}&")
  end
end

type_dependencies = lambda do |type|
  signatures = [type["baseType"], *type.fetch("directInterfaces", [])]
  type.fetch("members").each do |member|
    signatures.concat([member["type"], member["returnType"]])
    signatures.concat(member.fetch("parameters", []).map { |parameter| parameter["type"] })
  end
  signatures.compact.flat_map { |signature| extract_types.call(signature) }.uniq - [type.fetch("name")]
end

missing_labels = strict.fetch("details").fetch("MISSING_MEMBER")
reverse_edges = Hash.new { |hash, key| hash[key] = [] }
missing_labels.each do |label|
  owner, identity = label.split("::", 2)
  member_name = identity.sub(/ \(\d+ overloads?\)\z/, "")
  reference_by_name.fetch(owner).fetch("members").select { |member| member.fetch("name") == member_name }.each do |member|
    signatures = [member["type"], member["returnType"]]
    signatures.concat(member.fetch("parameters", []).map { |parameter| parameter["type"] })
    signatures.compact.flat_map { |signature| extract_types.call(signature) }.uniq.each do |dependency|
      reverse_edges[dependency] << label unless dependency == owner
    end
  end
end

candidates = reference.fetch("types").filter_map do |type|
  name = type.fetch("name")
  next if target_names.include?(name)

  dependencies = type_dependencies.call(type)
  unmet = dependencies - complete_names
  reverse = reverse_edges.fetch(name, []).uniq.sort
  expected = type.fetch("members").count do |member|
    !(type["kind"] == "enum" && member["name"] == "value__")
  end
  {
    "name" => name,
    "kind" => type.fetch("kind"),
    "expectedRubyIdentities" => expected,
    "dependencies" => dependencies.sort,
    "unmetDependencies" => unmet.sort,
    "partialRemainderReverseEdges" => reverse,
    "dependencyComplete" => unmet.empty?
  }
end

managed_enum_candidates = candidates.select do |candidate|
  candidate.fetch("kind") == "enum" && candidate.fetch("dependencyComplete") &&
    !candidate.fetch("partialRemainderReverseEdges").empty?
end.sort_by { |candidate| [candidate.fetch("expectedRubyIdentities"), candidate.fetch("name")] }

selected = managed_enum_candidates.first
abort "no dependency-complete managed enum is referenced by the selected partial remainder" unless selected

report = {
  "schemaVersion" => 1,
  "referenceTypes" => reference_by_name.length,
  "targetTypes" => target_names.length,
  "completeTypes" => complete_names.length,
  "partialTypes" => strict.fetch("partialTypes").keys,
  "missingTypes" => strict.fetch("missingTypeNames").length,
  "candidatePolicy" => "missing managed enum; all XNA public-signature dependencies complete; directly referenced by a selected partial remainder; fewest expected Ruby identities",
  "eligibleManagedEnums" => managed_enum_candidates,
  "selectedNext" => selected.merge("selectedOnly" => true, "started" => false)
}

destination = File.join(root, "docs", "generated", "public-signature-dependency-report.json")
File.write(destination, JSON.pretty_generate(report) + "\n")
puts "DEPENDENCY_CANDIDATES=#{managed_enum_candidates.length}"
puts "SELECTED_NEXT=#{selected.fetch("name")}"
puts "SELECTED_ONLY=true"
puts "STARTED=false"
