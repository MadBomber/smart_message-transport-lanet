# frozen_string_literal: true

require_relative "lib/smart_message/transport/lanet/version"

Gem::Specification.new do |spec|
  spec.name = "smart_message-transport-lanet"
  spec.version = SmartMessage::Transport::LanetVersion::VERSION
  spec.authors = ["Dewayne VanHoozer"]
  spec.email = ["dewayne@vanhoozer.me"]

  spec.summary = "LAN-based peer-to-peer transport for SmartMessage using Lanet"
  spec.description = "A SmartMessage transport adapter that enables peer-to-peer message communication over local area networks using the Lanet library. Provides automatic node discovery, heartbeat monitoring, and capability-based message routing."
  spec.homepage = "https://github.com/MadBomber/smart_message-transport-lanet"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/MadBomber/smart_message-transport-lanet"
    spec.metadata["changelog_uri"] = "https://github.com/MadBomber/smart_message-transport-lanet/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "smart_message"
  spec.add_dependency "lanet"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
