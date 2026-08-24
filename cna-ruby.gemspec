# frozen_string_literal: true

require_relative "lib/cna/version"

Gem::Specification.new do |spec|
  spec.name = "cna-ruby"
  spec.version = CNA::VERSION
  spec.authors = ["OpenEggbert contributors"]
  spec.summary = "Measured Ruby projection of selected XNA 4.0 API over the CNA C ABI"
  spec.description = "Foundation binding for desktop MRI Ruby. The selected XNA surface is intentionally incomplete."
  spec.homepage = "https://github.com/openeggbert/cna-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*.rb", "sig/**/*.rbs", "README.md", "LICENSE*", "NOTICE*"]
  end
  spec.require_paths = ["lib"]
  spec.metadata["source_code_uri"] = spec.homepage
end
