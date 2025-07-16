# frozen_string_literal: true

require_relative "lib/arel_attribute/version"

Gem::Specification.new do |spec|
  spec.name = "arel_attribute"
  spec.version = ArelAttribute::VERSION
  spec.authors = ["Keenan Brock"]
  spec.email = ["keenan@thebrocks.net"]

  spec.summary = "Provide arel for attributes to work in active record queries"
  spec.description = spec.summary
  spec.homepage = "https://github.com/kbrock/arel_attribute"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/kbrock/arel_attribute"
  spec.metadata["changelog_uri"] = "https://github.com/kbrock/arel_attribute/blob/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

#  spec.add_runtime_dependency "active_support"
#  spec.add_runtime_dependency "active_record"
  spec.add_runtime_dependency "rails" #kiss for now (since it is using rails head)

  spec.add_development_dependency "byebug"
  spec.add_development_dependency "database_cleaner-active_record", "~> 2.1"
  spec.add_development_dependency "db-query-matchers"
  spec.add_development_dependency "mysql2"
  spec.add_development_dependency "pg"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "standard", "~> 1.3"
  spec.add_development_dependency "simplecov", ">= 0.21.2"
  spec.add_development_dependency "sqlite3"
end
