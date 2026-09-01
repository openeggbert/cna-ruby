# frozen_string_literal: true

require_relative "signature_builder"

result = CNAApiCompat::SignatureBuilder.build
File.write(CNAApiCompat::SignatureBuilder.signatures_path, CNAApiCompat::SignatureBuilder.serialize(result))
puts "TARGET_TYPES=#{result.fetch("types").length}"
puts "TARGET_MEMBERS=#{result.fetch("types").sum { |type| type.fetch("members").length }}"
