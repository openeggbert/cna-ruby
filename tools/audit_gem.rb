# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "rubygems/package"
require "tmpdir"

gem_path = File.expand_path(ARGV.fetch(0) { abort "usage: audit_gem.rb GEM" })
package = Gem::Package.new(gem_path)
spec = package.spec
forbidden_entries = spec.files.grep(%r{(?:\A|/)(?:\.git|\.bundle|vendor|tmp|pkg|__pycache__)(?:/|\z)|\.(?:so|dll|dylib|a|o|class|jar)\z})
developer_leaks = []
Dir.mktmpdir("cna-ruby-gem-audit-") do |directory|
  package.extract_files(directory)
  spec.files.each do |entry|
    path = File.join(directory, entry)
    next unless File.file?(path)
    bytes = File.binread(path)
    developer_leaks << entry if bytes.include?("/rv/".b) || bytes.include?("/home/".b) || bytes.include?("../cna/build".b)
  end
end

report = {
  "schemaVersion" => 1,
  "GEM_FILENAME" => File.basename(gem_path),
  "VERSION" => spec.version.to_s,
  "GEM_SHA256" => Digest::SHA256.file(gem_path).hexdigest,
  "GEM_ENTRIES" => spec.files.length,
  "FORBIDDEN_ENTRIES" => forbidden_entries,
  "NATIVE_LIBRARIES_BUNDLED" => spec.files.grep(/\.(?:so|dll|dylib)\z/),
  "DEVELOPER_PATH_LEAKS" => developer_leaks,
  "entries" => spec.files.sort
}
File.write(File.expand_path("../docs/generated/package-report.json", __dir__), JSON.pretty_generate(report) + "\n")
puts "GEM_FILENAME=#{report["GEM_FILENAME"]}"
puts "GEM_SHA256=#{report["GEM_SHA256"]}"
puts "GEM_ENTRIES=#{report["GEM_ENTRIES"]}"
puts "FORBIDDEN_ENTRIES=#{forbidden_entries.length}"
puts "NATIVE_LIBRARIES_BUNDLED=#{report["NATIVE_LIBRARIES_BUNDLED"].length}"
puts "DEVELOPER_PATH_LEAKS=#{developer_leaks.length}"
abort "gem audit failed" unless forbidden_entries.empty? && developer_leaks.empty?
