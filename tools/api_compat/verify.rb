# frozen_string_literal: true

require "json"
require_relative "../../lib/cna"
require_relative "verifier"

mode = ARGV.delete("--strict") ? :strict : ARGV.delete("--leak-only") ? :leak_only : :report
reference = JSON.parse(File.read(File.expand_path("reference/xna40-windows-runtime-contract.json", __dir__)))
target = JSON.parse(File.read(File.expand_path("signatures.json", __dir__)))
result = CNAApiCompat::Verifier.new(reference: reference, target: target, runtime: true).verify

reference_types = reference.fetch("types")
reference_members = reference_types.sum { |type| type.fetch("members").length }
expected_members = reference_types.sum do |type|
  type.fetch("members").count { |member| !(type["kind"] == "enum" && member["name"] == "value__") }
end
target_members = target.fetch("types").sum { |type| type.fetch("members").length }
event_members = target.fetch("types").flat_map do |type|
  type.fetch("members").select { |member| member["kind"] == "event" }.map { |member| "#{type.fetch("name")}::#{member.fetch("name")}" }
end
event_owners = target.fetch("types").count { |type| type.fetch("members").any? { |member| member["kind"] == "event" } }
total = result.counts.values.sum
report = {
  "schemaVersion" => 1,
  "profile" => reference.fetch("profile"),
  "REFERENCE_TYPES" => reference_types.length,
  "REFERENCE_MEMBERS" => reference_members,
  "EXPECTED_RUBY_TYPES" => reference_types.length,
  "EXPECTED_RUBY_MEMBERS" => expected_members,
  "TARGET_TYPES" => target.fetch("types").length,
  "TARGET_MEMBERS" => target_members,
  "TOTAL_DIAGNOSTICS" => total,
  "COMPLETE_TYPES" => result.complete_types.length,
  "PARTIAL_TYPES" => result.partial_types.length,
  "MISSING_TYPES" => result.missing_types.length,
  "ALLOWLIST_ENTRIES" => 0,
  "EVENT_IDENTITIES" => event_members.length,
  "EVENT_OWNER_TYPES" => event_owners,
  "EVENT_SUPPORT_TYPE" => CNAApiCompat::EVENT_SUPPORT_TYPE,
  "BCL_PROJECTED_IDENTITIES" => CNA::Runtime::BclProjection.identities.length,
  "BCL_EXCEPTION_BASES" => CNA::Runtime::BclProjection::EXCEPTION_BASES.length,
  "BCL_THROWN_EXCEPTIONS" => CNA::Runtime::BclProjection::THROWN_EXCEPTIONS.length
}.merge(result.counts).merge(
  "eventIdentities" => event_members,
  "bclProjection" => {
    "types" => CNA::Runtime::BclProjection::TYPES,
    "exceptionBases" => CNA::Runtime::BclProjection::EXCEPTION_BASES,
    "thrownExceptions" => CNA::Runtime::BclProjection::THROWN_EXCEPTIONS
  },
  "completeTypeNames" => result.complete_types,
  "partialTypes" => result.partial_types,
  "missingTypeNames" => result.missing_types,
  "localDiagnostics" => target.fetch("types").to_h { |type| [type.fetch("name"), result.type_diagnostics(type.fetch("name"))] },
  "details" => result.details
)

json_path = File.expand_path("../../docs/generated/api-compat-report.json", __dir__)
File.write(json_path, JSON.pretty_generate(report) + "\n")
missing_path = File.expand_path("../../docs/generated/missing-type-inventory.md", __dir__)
File.write(missing_path, "# Missing type inventory\n\n" + result.missing_types.map { |name| "- `#{name}`" }.join("\n") + "\n")

report.each { |key, value| puts "#{key}=#{value}" if key.match?(/\A[A-Z_]+\z/) }
case mode
when :strict
  exit(total.zero? ? 0 : 1)
when :leak_only
  leak_categories = %w[UNEXPECTED_TYPE UNEXPECTED_MEMBER INTERNAL_TYPE_LEAK RAW_HANDLE_LEAK PUBLIC_NATIVE_FFI_LEAK]
  exit(leak_categories.sum { |category| result.counts.fetch(category) }.zero? ? 0 : 1)
end
