# frozen_string_literal: true

require_relative "lib/bg_service/version"

Gem::Specification.new do |spec|
  spec.name = "bg_service"
  spec.version = BgService::VERSION
  spec.authors = ["Carl Brasic"]
  spec.email = ["cbrasic@gmail.com"]

  spec.summary = "Run a network service as a subprocess for tests"
  spec.homepage = "https://github.com/brasic/bg_service"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/brasic/bg_service"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.start_with?("test/") || f.start_with?(".github/")
    end
  end

  spec.require_paths = ["lib"]
end
