# frozen_string_literal: true

require_relative "lib/baker/version"

Gem::Specification.new do |spec|
  spec.name = "bakerb"
  spec.version = Baker::VERSION
  spec.authors = ["Christopher Oezbek"]
  spec.email = ["c.oezbek@gmail.com"]

  spec.summary = "Baker is a Project-Setup-As-Code tool"
  spec.description = "Baker allows to define and execute tasks during new project setup (such as calling `rails new`)."
  spec.homepage = "https://github.com/coezbek/baker"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/coezbek/baker/blob/main/README.md#Changelog"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "tty-reader", "~> 0.9"
  spec.add_dependency "rainbow", "~> 3.1"
  spec.add_dependency "vtparser", "~> 0.1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
